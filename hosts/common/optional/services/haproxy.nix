# HAProxy reverse proxy with mTLS support for WAN access
# Security model:
#	- LAN (192.168.0.0/16): Standard TLS, no mTLS required
#	- WAN: mTLS required with step-ca client certificates
#
# Consumes custom.reverseProxy.virtualHosts declared by individual services.
# Only virtualHosts with backendHost set get HAProxy routing.
# ALL virtualHosts get ACME certificates.
#
# Troubleshooting ACME:
# If ACME certificates fail to renew, check these services:
#	- Main service: sudo systemctl status acme-<domain>.service
#	- Renewal service: sudo systemctl status acme-order-renew-<domain>.service
#	- View logs: sudo journalctl -u acme-order-renew-<domain>.service
# Common issues:
#   1. Old certificate metadata preventing renewal
#      Solution: Remove old data from /var/lib/acme/.lego/<domain>/
#   2. Certificate from wrong ACME account
#      Solution: Remove /var/lib/acme/.lego/<domain>/ and restart acme-order-renew
#   3. After adding a new virtualHost, HAProxy may need a manual restart to pick up the new certs:
#      sudo systemctl restart haproxy-cert-combine.service && sudo systemctl restart haproxy.service
#
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  # All declared virtualHosts (proxied and ACME-only)
  allHosts = config.custom.reverseProxy.virtualHosts;

  # Only virtualHosts with backends get HAProxy routing
  proxiedHosts = lib.filterAttrs (_: vh: vh.backendHost != null) allHosts;
  publicHosts = lib.filterAttrs (_: vh: vh.proxyWan && vh.mTLS) proxiedHosts;
  publicNoMtlsHosts = lib.filterAttrs (_: vh: vh.proxyWan && !vh.mTLS) proxiedHosts;
  lanHosts = lib.filterAttrs (_: vh: !vh.proxyWan) proxiedHosts;

  # mTLS CA bundle from step-ca
  mTLSCaFile = "/mnt/storage/step-ca/.step/certs/ca_bundle.crt";

  # Container bridge subnets (treated as LAN, no mTLS required)
  containerSubnets = lib.concatStringsSep " " (
    lib.mapAttrsToList (_: net: net.subnet) config.hostSpec.networking.containerNetworks
  );

  # Port allocation for internal HAProxy frontends
  # We need unique ports for each service's mTLS and LAN frontends
  # Strategy: Use a sorted list of service names to ensure consistent port assignment
  # mTLS ports: 8443, 8444, 8445, ... (one per public service)
  # LAN ports: Start after all mTLS ports + 10 port buffer (one per all proxied services)
  sortedAllServices = lib.sort (a: b: a < b) (lib.attrNames proxiedHosts);
  sortedPublicServices = lib.sort (a: b: a < b) (lib.attrNames publicHosts);

  getPublicServiceIndex =
    name:
    let
      idx = lib.lists.findFirstIndex (x: x == name) null sortedPublicServices;
    in
    if idx == null then 0 else idx;

  getAllServiceIndex =
    name:
    let
      idx = lib.lists.findFirstIndex (x: x == name) null sortedAllServices;
    in
    if idx == null then 0 else idx;

  getMtlsPort = name: 8443 + (getPublicServiceIndex name);
  getLanPort = name: 8443 + (lib.length sortedPublicServices) + 10 + (getAllServiceIndex name);

  # Generate SNI ACL for a service
  mkSniAcl = name: cfg: "acl is_${name} req_ssl_sni -i ${cfg.domain}";

  # Generate backend routing for public services (WAN with mTLS, LAN without)
  mkPublicRouting = name: cfg: ''
    use_backend https-${name}-mtls-backend if is_${name} !is_lan
    use_backend https-${name}-lan-backend if is_${name} is_lan'';

  # Generate backend routing for public services without mTLS (WAN + LAN, no client cert)
  mkPublicNoMtlsRouting = name: cfg: ''use_backend https-${name}-lan-backend if is_${name}'';

  # Generate backend routing for LAN-only services
  mkLanRouting = name: cfg: ''use_backend https-${name}-lan-backend if is_${name} is_lan'';

  # Generate TCP backend that routes to internal frontend
  mkTcpBackend = name: type: port: ''
    backend https-${name}-${type}-backend
      mode tcp
      server ${name}-${type} 127.0.0.1:${toString port}'';

  # Generate path-based ACLs and use_backend rules for extraBackends
  mkExtraBackendRouting =
    name: cfg:
    lib.concatStringsSep "\n      " (
      lib.mapAttrsToList (ebName: eb: ''
              acl is_${name}_${ebName} path_beg ${eb.pathPrefix}
        ${lib.optionalString (eb.allowMethods != null) ''
          acl is_${name}_${ebName}_method method ${lib.concatStringsSep " " eb.allowMethods}
          http-request deny if is_${name}_${ebName} !is_${name}_${ebName}_method''}
        ${lib.optionalString (
          eb.hostHeader != null
        ) ''http-request set-header Host ${eb.hostHeader} if is_${name}_${ebName}''}
              use_backend ${name}-${ebName} if is_${name}_${ebName}'') cfg.extraBackends
    );

  # Escape for HAProxy "string" directive (double-quoted)
  escapeHaproxyString = s: lib.replaceStrings [ "\\" "\"" ] [ "\\\\" "\\\"" ] s;

  # Generate HTTP frontend with mTLS
  mkMtlsFrontend = name: cfg: ''
        frontend https-${name}-mtls
          bind 127.0.0.1:${toString (getMtlsPort name)} ssl crt /var/lib/acme/${cfg.domain}/full.pem ca-file ${mTLSCaFile} verify required${
            if cfg.backendH2 then " alpn h2,http/1.1" else ""
          }
          mode http
    ${lib.optionalString cfg.backendH2 ''
      # Extended timeouts for gRPC/HTTP2 long-lived connections
      timeout client 3600s
      timeout server 3600s
    ''}
          # Set headers
          http-request set-header Host ${cfg.domain}
          http-request set-header X-Forwarded-Host ${cfg.domain}
          http-request set-header X-Forwarded-Proto https
          http-request set-header X-Forwarded-For %[src]
          http-request add-header X-SSL-Client-Verify %[ssl_c_verify]
          http-request add-header X-SSL-Client-DN %{+Q}[ssl_c_s_dn]
${lib.optionalString (cfg.oidcDiscovery != null) ''
      acl is_${name}_oidc_discovery path -i ${cfg.oidcDiscovery.path}
      http-request return status 200 content-type application/json hdr Access-Control-Allow-Origin "*" string "${escapeHaproxyString cfg.oidcDiscovery.json}" if is_${name}_oidc_discovery
''}
    ${lib.optionalString (cfg.extraBackends != { }) ''
      # Path-based routing to extra backends
      ${lib.optionalString (cfg.extraBackends ? oidcToken) ''
        # Rate limit OIDC token exchange by client IP
        stick-table type ip size 10k expire 10m store http_req_rate(10s),http_req_rate(10m)
        http-request track-sc0 src if is_${name}_oidcToken
        http-request deny if is_${name}_oidcToken { sc_http_req_rate(0) gt 5 } || { sc_http_req_rate(1) gt 30 }
      ''}
      ${mkExtraBackendRouting name cfg}
    ''}
          default_backend ${name}'';

  # Generate HTTP frontend without mTLS (LAN only)
  mkLanFrontend = name: cfg: ''
        frontend https-${name}-lan
          bind 127.0.0.1:${toString (getLanPort name)} ssl crt /var/lib/acme/${cfg.domain}/full.pem${
            if cfg.backendH2 then " alpn h2,http/1.1" else ""
          }
          mode http
    ${lib.optionalString cfg.backendH2 ''
      # Extended timeouts for gRPC/HTTP2 long-lived connections
      timeout client 3600s
      timeout server 3600s
    ''}
          http-request set-header Host ${cfg.domain}
          http-request set-header X-Forwarded-Host ${cfg.domain}
          http-request set-header X-Forwarded-Proto https
          http-request set-header X-Forwarded-For %[src]
${lib.optionalString (cfg.oidcDiscovery != null) ''
      acl is_${name}_oidc_discovery path -i ${cfg.oidcDiscovery.path}
      http-request return status 200 content-type application/json hdr Access-Control-Allow-Origin "*" string "${escapeHaproxyString cfg.oidcDiscovery.json}" if is_${name}_oidc_discovery
''}
    ${lib.optionalString (cfg.extraBackends != { }) ''
      # Path-based routing to extra backends
      ${mkExtraBackendRouting name cfg}
    ''}
          default_backend ${name}'';

  # Generate HTTP backend
  mkHttpBackend = name: cfg: ''
    backend ${name}
      mode http${lib.optionalString cfg.backendH2 "\n      timeout server 3600s"}
      server ${name} ${cfg.backendHost}:${toString cfg.backendPort}${
        if cfg.backendSSL then " ssl verify none" else ""
      }${if cfg.backendH2 then " proto h2" else ""}'';

  # Generate extra path-based backends for a virtualHost
  mkExtraBackends =
    name: cfg:
    lib.concatStringsSep "\n\n      " (
      lib.mapAttrsToList (ebName: eb: ''
        backend ${name}-${ebName}
          mode http${
            lib.optionalString (
              if eb.backendH2 == null then cfg.backendH2 else eb.backendH2
            ) "\n      timeout server 3600s"
          }
          server ${name}-${ebName} ${eb.backendHost}:${toString eb.backendPort}${
            if eb.backendSSL then " ssl verify none" else ""
          }${if eb.backendSNI != null then " sni str(${eb.backendSNI})" else ""}${
            if (if eb.backendH2 == null then cfg.backendH2 else eb.backendH2) then " proto h2" else ""
          }'') cfg.extraBackends
    );
in
{
  imports = [ ./cloudflare-dyndns.nix ];

  # ACME credentials for certificate provisioning
  sops.secrets."cloudflare/acme-env" = {
    sopsFile = "${builtins.toString inputs.nix-secrets}/sops/${config.hostSpec.hostName}.yaml";
    owner = "acme";
    group = "acme";
    mode = "0400";
  };

  services.haproxy = {
    enable = true;

    config = ''
      global
        log /dev/log local0
        log /dev/log local1 notice
        stats socket /run/haproxy/admin.sock mode 660 level admin
        stats timeout 30s
        user haproxy
        group haproxy
        daemon

        # Intermediate configuration
        ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
        ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
        ssl-default-bind-options prefer-client-ciphers no-sslv3 no-tlsv10 no-tlsv11 no-tls-tickets

        ssl-default-server-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
        ssl-default-server-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
        ssl-default-server-options no-sslv3 no-tlsv10 no-tlsv11 no-tls-tickets

      defaults
        log global
        mode http
        option httplog
        option dontlognull
        timeout connect 5000
        timeout client  50000
        timeout server  50000

      # HTTP frontend - redirect to HTTPS
      frontend http-in
        bind *:80
        bind :::80 v4v6
        mode http
        # Redirect all HTTP to HTTPS
        http-request redirect scheme https code 301

      # TCP frontend to inspect SNI and route to correct SSL frontend
      frontend https-dispatcher
        bind *:443
        bind :::443 v4v6
        mode tcp
        option tcplog

        # Define LAN network and WireGuard VPN (IPv4 and IPv6)
        # Includes standard RFC1918, ULA (fd00::/8), and Link-Local (fe80::/10)
        acl is_lan src ${config.hostSpec.networking.localSubnet} ${config.hostSpec.networking.wireguardIPv4Subnet} ${config.hostSpec.networking.localIPv6Subnet} ${config.hostSpec.networking.wireguardIPv6Subnet} 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10 fc00::/7 fe80::/10 2a00::/12 ${containerSubnets}

        # Inspect SNI to determine routing
        tcp-request inspect-delay 5s
        tcp-request content accept if { req_ssl_hello_type 1 }

        # SNI ACLs for all proxied domains
        ${lib.concatStringsSep "\n        " (lib.mapAttrsToList mkSniAcl proxiedHosts)}

        # Routing rules for public domains (WAN with mTLS, LAN without)
        ${lib.concatStringsSep "\n        " (lib.mapAttrsToList mkPublicRouting publicHosts)}

        # Routing rules for public domains without mTLS (WAN + LAN, no client cert)
        ${lib.concatStringsSep "\n        " (lib.mapAttrsToList mkPublicNoMtlsRouting publicNoMtlsHosts)}

        # Routing rules for LAN-only domains
        ${lib.concatStringsSep "\n        " (lib.mapAttrsToList mkLanRouting lanHosts)}

      # TCP backends - generate mTLS backends for public services and LAN backends for all proxied services
      ${lib.concatStringsSep "\n\n      " (
        # mTLS backends for public services
        (lib.mapAttrsToList (name: _: mkTcpBackend name "mtls" (getMtlsPort name)) publicHosts)
        ++
          # LAN backends for all proxied services
          (lib.mapAttrsToList (name: _: mkTcpBackend name "lan" (getLanPort name)) proxiedHosts)
      )}

      # HTTP frontends with mTLS (WAN access)
      ${lib.concatStringsSep "\n\n      " (lib.mapAttrsToList mkMtlsFrontend publicHosts)}

      # HTTP frontends without mTLS (LAN access)
      ${lib.concatStringsSep "\n\n      " (lib.mapAttrsToList mkLanFrontend proxiedHosts)}

      # HTTP backend definitions
      ${lib.concatStringsSep "\n\n      " (lib.mapAttrsToList mkHttpBackend proxiedHosts)}

      # Extra path-based backends
      ${lib.concatStringsSep "\n\n      " (
        lib.filter (s: s != "") (
          lib.mapAttrsToList (
            name: cfg: if cfg.extraBackends != { } then mkExtraBackends name cfg else ""
          ) proxiedHosts
        )
      )}
    '';
  };

  # Create haproxy user if it doesn't exist
  users.users.haproxy = {
    isSystemUser = true;
    group = "haproxy";
  };
  users.groups.haproxy = { };

  # Add haproxy to ca-proxy group for reading step-ca certificates
  users.users.haproxy.extraGroups = [ "ca-proxy" ];

  # Open firewall ports
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  # Systemd service configurations
  systemd.services = lib.mkMerge [
    {
      # Create HAProxy-compatible combined certificate files (proxied hosts only)
      haproxy-cert-combine = {
        description = "Combine ACME certificates for HAProxy";
        after = lib.mapAttrsToList (_: vh: "acme-${vh.domain}.service") proxiedHosts;
        wants = lib.mapAttrsToList (_: vh: "acme-${vh.domain}.service") proxiedHosts;
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          ${lib.concatStringsSep "\n      " (
            lib.mapAttrsToList (_: vh: ''
              if [ -f /var/lib/acme/${vh.domain}/key.pem ]; then
                cat /var/lib/acme/${vh.domain}/fullchain.pem \
                    /var/lib/acme/${vh.domain}/key.pem \
                    > /var/lib/acme/${vh.domain}/full.pem
                chmod 640 /var/lib/acme/${vh.domain}/full.pem
                chgrp haproxy /var/lib/acme/${vh.domain}/full.pem
              fi
            '') proxiedHosts
          )}
        '';
      };

      # Ensure HAProxy waits for combined certificates
      # Note: HAProxy uses the persistent CA bundle from /mnt/storage/step-ca/
      # and does NOT need the step-ca container running to start.
      # The container depends on HAProxy (for OIDC discovery), not the other way around.
      haproxy = {
        after = [
          "haproxy-cert-combine.service"
          "step-ca-fix-cert-permissions.service"
        ];
        wants = [
          "haproxy-cert-combine.service"
          "step-ca-fix-cert-permissions.service"
        ];
      };

      # Base domain ACME waits for DNS
      "acme-${config.hostSpec.domain}" = {
        after = [ "cloudflare-dyndns.service" ];
        wants = [ "cloudflare-dyndns.service" ];
      };
    }

    # ALL virtualHost ACME certificates wait for DNS
    (lib.mapAttrs' (
      _: vh:
      lib.nameValuePair "acme-${vh.domain}" {
        after = [ "cloudflare-dyndns.service" ];
        wants = [ "cloudflare-dyndns.service" ];
      }
    ) allHosts)
  ];

  # ACME configuration - certificates for ALL virtualHosts (proxied and ACME-only)
  security.acme = {
    acceptTerms = true;
    defaults = {
      email = config.hostSpec.services.acme.email;
      dnsProvider = config.hostSpec.services.acme.dnsProvider;
      environmentFile = config.sops.secrets."cloudflare/acme-env".path;
      dnsPropagationCheck = true;
      group = "haproxy";
      keyType = "ec256";
      dnsResolver = "1.1.1.1:53";
    };

    # Dynamically generate certificates for base domain and all virtualHosts
    certs = lib.mkMerge [
      # Base domain certificate
      {
        "${config.hostSpec.domain}" = {
          domain = config.hostSpec.domain;
          webroot = null;
        };
      }
      # VirtualHost domain certificates
      (lib.mapAttrs' (
        _: vh:
        lib.nameValuePair vh.domain {
          domain = vh.domain;
          webroot = null;
          reloadServices = [
            "haproxy-cert-combine.service"
            "haproxy.service"
          ];
        }
      ) allHosts)
    ];
  };
}
