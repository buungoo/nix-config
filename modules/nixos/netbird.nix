# Netbird mesh VPN server (management + signal)
# Proxied through HAProxy with mTLS, OIDC via Kanidm
# No dashboard, no coturn — declarative config only
{
  config,
  lib,
  inputs,
  ...
}:
let
  cfg = config.custom.services.netbird;
  authDomain = config.custom.reverseProxy.virtualHosts.auth.domain;
  sopsFolder = builtins.toString inputs.nix-secrets + "/sops";
in
{
  options.custom.services.netbird = {
    enable = lib.mkEnableOption "Netbird mesh VPN server with Kanidm OIDC";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "netbird.${config.hostSpec.domain}";
      description = "FQDN for the Netbird server";
    };
  };

  config = lib.mkIf cfg.enable {
    # ── Netbird server services ──────────────────────────────────────
    services.netbird.server = {
      enable = true;
      domain = cfg.domain;
      enableNginx = false; # HAProxy handles reverse proxying

      management = {
        oidcConfigEndpoint = "https://${authDomain}/oauth2/openid/netbird/.well-known/openid-configuration";
        turnDomain = cfg.domain; # Required by module; overridden in settings below
        singleAccountModeDomain = config.hostSpec.domain;
        dnsDomain = "netbird.selfhosted";
        disableAnonymousMetrics = true;

        settings = {
          # Datastore encryption — MUST be overridden from default
          DataStoreEncryptionKey._secret =
            config.sops.secrets."netbird/datastore-encryption-key".path;

          # Public STUN servers (no self-hosted coturn)
          Stuns = [
            {
              Proto = "udp";
              URI = "stun:stun.l.google.com:19302";
              Username = "";
              Password = null;
            }
          ];

          # TURN disabled (no coturn)
          TURNConfig = {
            Turns = [ ];
            TimeBasedCredentials = false;
            Secret = "unused";
          };

          # Signal server — same domain, HAProxy routes by path
          Signal = {
            Proto = "https";
            URI = "${cfg.domain}:443";
            Username = "";
            Password = null;
          };

          # Trust HAProxy forwarded headers
          ReverseProxy = {
            TrustedHTTPProxies = [ "127.0.0.1/32" ];
            TrustedHTTPProxiesCount = 1;
            TrustedPeers = [ "127.0.0.1/32" ];
          };

          # PKCE authorization flow for CLI/agent login
          PKCEAuthorizationFlow.ProviderConfig = {
            Audience = "netbird";
            ClientID = "netbird";
            ClientSecret = "";
            Scope = "openid profile email";
            RedirectURLs = [ "http://localhost:53000" ];
            UseIDToken = true;
          };

          # No IDP manager integration (users created on first OIDC login)
          IdpManagerConfig.ManagerType = "none";
        };
      };

      signal = { };

      dashboard.enable = false;
      coturn.enable = false;
    };

    # ── Reverse proxy (HAProxy) ──────────────────────────────────────
    custom.reverseProxy.virtualHosts.netbird = {
      domain = cfg.domain;
      backendHost = "127.0.0.1";
      backendPort = config.services.netbird.server.management.port;
      backendSSL = false;
      backendH2 = true;
      mTLS = false; # Netbird clients can't present step-ca certs; auth via OIDC instead
      extraBackends.signal = {
        pathPrefix = "/signalexchange.SignalExchange/";
        backendHost = "127.0.0.1";
        backendPort = config.services.netbird.server.signal.port;
      };
    };

    # ── Kanidm OIDC client ───────────────────────────────────────────
    custom.kanidm.oauthClients.netbird = {
      displayName = "Netbird VPN";
      public = true;
      originUrl = [
        "https://${cfg.domain}/api/auth/callback"
        "http://localhost:53000"
      ];
      originLanding = "https://${cfg.domain}/";
      scopeMap.netbird_users = [
        "openid"
        "email"
        "profile"
      ];
    };

    # ── SOPS secrets ─────────────────────────────────────────────────
    sops.secrets."netbird/datastore-encryption-key" = {
      sopsFile = "${sopsFolder}/shared.yaml";
      owner = "root";
      group = "root";
      mode = "0400";
    };
  };
}
