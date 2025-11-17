package main

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"sync"
	"software.sslmate.com/src/go-pkcs12"

	"github.com/coreos/go-oidc/v3/oidc"
	"golang.org/x/oauth2"
)

var (
	oauth2Config *oauth2.Config
	oidcVerifier *oidc.IDTokenVerifier
	stepCAURL    string

	// Store PKCE verifiers temporarily (state -> verifier)
	pkceVerifiers = make(map[string]string)
	pkceMutex     sync.Mutex
)

// Step-CA API structures
type signRequest struct {
	CsrPEM string `json:"csr"`
	OTT    string `json:"ott"`
}

type signResponse struct {
	CertPEM string   `json:"crt"`
	CaPEM   string   `json:"ca"`
	ChainPEM []string `json:"certChain,omitempty"`
}

func main() {
	// Configuration from environment
	kanidmURL := mustGetEnv("KANIDM_URL")
	clientID := getEnv("OIDC_CLIENT_ID", "step-ca-enroll")
	clientSecret := mustGetEnv("OIDC_CLIENT_SECRET")
	redirectURL := mustGetEnv("REDIRECT_URL")
	stepCAURL = mustGetEnv("STEP_CA_URL")
	bindAddr := getEnv("BIND_ADDR", "127.0.0.1:3000")

	// Configure OIDC provider
	// Use step-ca-enroll discovery endpoint (not step-ca)
	ctx := context.Background()
	provider, err := oidc.NewProvider(ctx, kanidmURL+"/oauth2/openid/"+clientID)
	if err != nil {
		log.Fatalf("Failed to create OIDC provider: %v", err)
	}

	// Configure OAuth2
	oauth2Config = &oauth2.Config{
		ClientID:     clientID,
		ClientSecret: clientSecret,
		RedirectURL:  redirectURL,
		Endpoint:     provider.Endpoint(),
		Scopes:       []string{oidc.ScopeOpenID, "email", "profile"},
	}

	// Debug: Log the OAuth2 configuration
	log.Printf("OAuth2 Config - ClientID: %s, RedirectURL: %s", clientID, redirectURL)
	log.Printf("OAuth2 Endpoint - AuthURL: %s, TokenURL: %s", oauth2Config.Endpoint.AuthURL, oauth2Config.Endpoint.TokenURL)

	oidcVerifier = provider.Verifier(&oidc.Config{ClientID: clientID})

	// Setup HTTP handlers
	http.HandleFunc("/enroll", handleEnroll)
	http.HandleFunc("/callback", handleCallback)
	http.HandleFunc("/health", handleHealth)

	log.Printf("Starting step-ca enrollment service on %s", bindAddr)
	if err := http.ListenAndServe(bindAddr, nil); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	fmt.Fprint(w, "OK")
}

func handleEnroll(w http.ResponseWriter, r *http.Request) {
	log.Println("Starting enrollment flow")

	// Generate random state
	state := randomString(32)

	// Generate PKCE code verifier (random string 43-128 chars)
	codeVerifier := randomString(64) // 64 bytes = 128 hex chars

	// Generate PKCE code challenge (SHA256 hash of verifier, base64url encoded)
	hash := sha256.Sum256([]byte(codeVerifier))
	codeChallenge := base64.RawURLEncoding.EncodeToString(hash[:])

	// Store verifier for later use in callback
	pkceMutex.Lock()
	pkceVerifiers[state] = codeVerifier
	pkceMutex.Unlock()

	// Redirect to OAuth provider with PKCE parameters
	authURL := oauth2Config.AuthCodeURL(
		state,
		oauth2.AccessTypeOffline,
		oauth2.SetAuthURLParam("code_challenge", codeChallenge),
		oauth2.SetAuthURLParam("code_challenge_method", "S256"),
	)
	http.Redirect(w, r, authURL, http.StatusFound)
}

func handleCallback(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	// Get state parameter
	state := r.URL.Query().Get("state")
	if state == "" {
		http.Error(w, "No state in request", http.StatusBadRequest)
		return
	}

	// Retrieve PKCE code verifier
	pkceMutex.Lock()
	codeVerifier, ok := pkceVerifiers[state]
	if ok {
		delete(pkceVerifiers, state) // Remove after use
	}
	pkceMutex.Unlock()

	if !ok {
		log.Printf("No PKCE verifier found for state: %s", state)
		http.Error(w, "Invalid state", http.StatusBadRequest)
		return
	}

	// Exchange code for token with PKCE verifier
	code := r.URL.Query().Get("code")
	if code == "" {
		http.Error(w, "No code in request", http.StatusBadRequest)
		return
	}

	// Exchange code for token with PKCE verifier
	// Use VerifierOption to send code_verifier in the token request body
	log.Printf("Exchanging code for token - code: %s..., verifier length: %d", code[:20], len(codeVerifier))
	token, err := oauth2Config.Exchange(
		ctx,
		code,
		oauth2.VerifierOption(codeVerifier),
	)
	if err != nil {
		log.Printf("Failed to exchange token: %v", err)
		log.Printf("Error details - Type: %T", err)
		http.Error(w, fmt.Sprintf("Failed to exchange token: %v", err), http.StatusInternalServerError)
		return
	}
	log.Printf("Token exchange successful")

	// Extract ID token
	rawIDToken, ok := token.Extra("id_token").(string)
	if !ok {
		http.Error(w, "No id_token in response", http.StatusInternalServerError)
		return
	}

	// Verify ID token
	idToken, err := oidcVerifier.Verify(ctx, rawIDToken)
	if err != nil {
		log.Printf("Failed to verify ID token: %v", err)
		http.Error(w, "Failed to verify ID token", http.StatusInternalServerError)
		return
	}

	// Extract email from claims
	var claims struct {
		Email string `json:"email"`
	}
	if err := idToken.Claims(&claims); err != nil {
		http.Error(w, "Failed to parse claims", http.StatusInternalServerError)
		return
	}

	log.Printf("Authenticated user: %s", claims.Email)

	// Generate ECDSA key pair
	privateKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		log.Printf("Failed to generate key: %v", err)
		http.Error(w, "Failed to generate key", http.StatusInternalServerError)
		return
	}

	// Create CSR
	csrTemplate := &x509.CertificateRequest{
		Subject: pkix.Name{
			CommonName: claims.Email,
		},
		EmailAddresses: []string{claims.Email},
	}

	csrDER, err := x509.CreateCertificateRequest(rand.Reader, csrTemplate, privateKey)
	if err != nil {
		log.Printf("Failed to create CSR: %v", err)
		http.Error(w, "Failed to create CSR", http.StatusInternalServerError)
		return
	}

	// Sign CSR with step-ca using OIDC token
	signedCert, caCerts, err := signCSR(ctx, csrDER, rawIDToken)
	if err != nil {
		log.Printf("Failed to sign CSR: %v", err)
		http.Error(w, "Failed to sign CSR", http.StatusInternalServerError)
		return
	}

	// Package certificate + private key + CA chain as .p12
	// Use password from environment variable, default to empty string
	p12Password := getEnv("P12_PASSWORD", "")
	p12Data, err := pkcs12.Encode(rand.Reader, privateKey, signedCert, caCerts, p12Password)
	if err != nil {
		log.Printf("Failed to create PKCS12: %v", err)
		http.Error(w, "Failed to create PKCS12", http.StatusInternalServerError)
		return
	}

	// Return .p12 file
	w.Header().Set("Content-Type", "application/x-pkcs12")
	w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=%s.p12", claims.Email))
	w.Write(p12Data)
}

func signCSR(ctx context.Context, csrDER []byte, oidcToken string) (*x509.Certificate, []*x509.Certificate, error) {
	// Convert CSR DER to PEM
	csrPEM := pem.EncodeToMemory(&pem.Block{
		Type:  "CERTIFICATE REQUEST",
		Bytes: csrDER,
	})

	// Prepare request to step-ca
	reqBody := signRequest{
		CsrPEM: string(csrPEM),
		OTT:    oidcToken,
	}

	reqJSON, err := json.Marshal(reqBody)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	// Create HTTP client that skips TLS verification (step-ca uses self-signed cert internally)
	transport := &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}
	client := &http.Client{Transport: transport}

	// Call step-ca sign API
	req, err := http.NewRequestWithContext(ctx, "POST", stepCAURL+"/1.0/sign", bytes.NewBuffer(reqJSON))
	if err != nil {
		return nil, nil, fmt.Errorf("failed to create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to call step-ca API: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusCreated {
		body, _ := io.ReadAll(resp.Body)
		log.Printf("step-ca sign request failed - Status: %d, Response: %s", resp.StatusCode, string(body))
		log.Printf("Request details - CSR length: %d, Token length: %d", len(csrPEM), len(oidcToken))
		return nil, nil, fmt.Errorf("step-ca API returned %d: %s", resp.StatusCode, string(body))
	}

	// Parse response
	var signResp signResponse
	if err := json.NewDecoder(resp.Body).Decode(&signResp); err != nil {
		return nil, nil, fmt.Errorf("failed to decode response: %w", err)
	}

	// Parse certificate
	certBlock, _ := pem.Decode([]byte(signResp.CertPEM))
	if certBlock == nil {
		return nil, nil, fmt.Errorf("failed to decode certificate PEM")
	}

	cert, err := x509.ParseCertificate(certBlock.Bytes)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to parse certificate: %w", err)
	}

	// Parse CA certificate
	var caCerts []*x509.Certificate
	if signResp.CaPEM != "" {
		caBlock, _ := pem.Decode([]byte(signResp.CaPEM))
		if caBlock != nil {
			caCert, err := x509.ParseCertificate(caBlock.Bytes)
			if err == nil {
				caCerts = append(caCerts, caCert)
			}
		}
	}

	// Parse chain if available
	for _, chainPEM := range signResp.ChainPEM {
		chainBlock, _ := pem.Decode([]byte(chainPEM))
		if chainBlock != nil {
			chainCert, err := x509.ParseCertificate(chainBlock.Bytes)
			if err == nil {
				caCerts = append(caCerts, chainCert)
			}
		}
	}

	return cert, caCerts, nil
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func mustGetEnv(key string) string {
	value := os.Getenv(key)
	if value == "" {
		log.Fatalf("%s environment variable must be set", key)
	}
	return value
}

func randomString(length int) string {
	bytes := make([]byte, length)
	rand.Read(bytes)
	return fmt.Sprintf("%x", bytes)
}
