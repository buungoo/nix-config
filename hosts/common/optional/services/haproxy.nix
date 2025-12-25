# HAProxy reverse proxy with mTLS support for WAN access
# Security model:
#	- LAN (192.168.0.0/16): Standard TLS, no mTLS required
#	- WAN: mTLS required with step-ca client certificates
#	- All services: immich.<domain>.<TLD>, auth<domain>.<TLD>, ca.<domain>.<TLD>, jellyfin.<domain>.<TLD>
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
#
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  # Get all public domains from hostSpec
  publicDomains = lib.filterAttrs (name: cfg: cfg.public) config.hostSpec.domains;
  # Get all LAN-only domains
  lanDomains = lib.filterAttrs (name: cfg: !cfg.public) config.hostSpec.domains;
  # All domains (public + LAN)
  allDomains = config.hostSpec.domains;

  # Port allocation for internal HAProxy frontends
  # We need unique ports for each service's mTLS and LAN frontends
  # Strategy: Use a sorted list of service names to ensure consistent port assignment
  # mTLS ports: 8443, 8444, 8445, ... (one per public service)
  # LAN ports: Start after all mTLS ports + 10 port buffer (one per all services)
  sortedAllServices = lib.sort (a: b: a < b) (lib.attrNames allDomains);
  sortedPublicServices = lib.sort (a: b: a < b) (lib.attrNames publicDomains);

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

  # Generate backend routing for LAN-only services
  mkLanRouting = name: cfg: ''use_backend https-${name}-lan-backend if is_${name} is_lan'';

  # Generate TCP backend that routes to internal frontend
  mkTcpBackend = name: port: ''
    backend https-${name}-${if port < 8446 then "mtls" else "lan"}-backend
      mode tcp
      server ${name}-${if port < 8446 then "mtls" else "lan"} 127.0.0.1:${toString port}'';

  # Generate HTTP frontend with mTLS
  mkMtlsFrontend = name: cfg: ''
    frontend https-${name}-mtls
      bind 127.0.0.1:${toString (getMtlsPort name)} ssl crt /var/lib/acme/${cfg.domain}/full.pem ca-file /mnt/storage/step-ca/.step/certs/ca_bundle.crt verify required
      mode http

      # Set headers
      http-request set-header X-Forwarded-Proto https
      http-request set-header X-Forwarded-For %[src]
      http-request add-header X-SSL-Client-Verify %[ssl_c_verify]
      http-request add-header X-SSL-Client-DN %{+Q}[ssl_c_s_dn]

      default_backend ${name}'';

  # Generate HTTP frontend without mTLS (LAN only)
  mkLanFrontend = name: cfg: ''
    frontend https-${name}-lan
      bind 127.0.0.1:${toString (getLanPort name)} ssl crt /var/lib/acme/${cfg.domain}/full.pem
      mode http

      http-request set-header X-Forwarded-Proto https
      http-request set-header X-Forwarded-For %[src]

      default_backend ${name}'';

  # Generate HTTP backend
  mkHttpBackend = name: cfg: ''
    backend ${name}
      mode http
      server ${name} ${cfg.backendHost}:${toString cfg.backendPort}${
        if cfg.backendSSL then " ssl verify none" else ""
      }'';
in
{
  imports = [ ./cloudflare-dyndns.nix ];

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
        acl is_lan src ${config.hostSpec.networking.localSubnet} ${config.hostSpec.networking.wireguardIPv4Subnet} ${config.hostSpec.networking.localIPv6Subnet} ${config.hostSpec.networking.wireguardIPv6Subnet}

        # Inspect SNI to determine routing
        tcp-request inspect-delay 5s
        tcp-request content accept if { req_ssl_hello_type 1 }

        # SNI ACLs for all configured domains
        ${lib.concatStringsSep "\n        " (lib.mapAttrsToList mkSniAcl allDomains)}

        # Routing rules for public domains (WAN with mTLS, LAN without)
        ${lib.concatStringsSep "\n        " (lib.mapAttrsToList mkPublicRouting publicDomains)}

        # Routing rules for LAN-only domains
        ${lib.concatStringsSep "\n        " (lib.mapAttrsToList mkLanRouting lanDomains)}

      # TCP backends - generate mTLS backends for public services and LAN backends for all services
      ${lib.concatStringsSep "\n\n      " (
        # mTLS backends for public services
        (lib.mapAttrsToList (name: cfg: mkTcpBackend name (getMtlsPort name)) publicDomains)
        ++
          # LAN backends for all services
          (lib.mapAttrsToList (name: cfg: mkTcpBackend name (getLanPort name)) allDomains)
      )}

      # HTTP frontends with mTLS (public services only)
      ${lib.concatStringsSep "\n\n      " (lib.mapAttrsToList mkMtlsFrontend publicDomains)}

      # HTTP frontends without mTLS (all services - LAN access)
      ${lib.concatStringsSep "\n\n      " (lib.mapAttrsToList mkLanFrontend allDomains)}

      # HTTP backend definitions
      ${lib.concatStringsSep "\n\n      " (lib.mapAttrsToList mkHttpBackend allDomains)}
    '';
  };

  # Create haproxy user if it doesn't exist
  users.users.haproxy = {
    isSystemUser = true;
    group = "haproxy";
  };
  users.groups.haproxy = {
    gid = 991;
  };

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
      # Create HAProxy-compatible combined certificate files
      haproxy-cert-combine = {
        description = "Combine ACME certificates for HAProxy";
        after = map (name: "acme-${config.hostSpec.domains.${name}.domain}.service") (
          lib.attrNames allDomains
        );
        wants = map (name: "acme-${config.hostSpec.domains.${name}.domain}.service") (
          lib.attrNames allDomains
        );
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          ${lib.concatStringsSep "\n      " (
            lib.mapAttrsToList (name: cfg: ''
              if [ -f /var/lib/acme/${cfg.domain}/key.pem ]; then
                cat /var/lib/acme/${cfg.domain}/fullchain.pem \
                    /var/lib/acme/${cfg.domain}/key.pem \
                    > /var/lib/acme/${cfg.domain}/full.pem
                chmod 640 /var/lib/acme/${cfg.domain}/full.pem
                chgrp haproxy /var/lib/acme/${cfg.domain}/full.pem
              fi
            '') allDomains
          )}
        '';
      };

      # Ensure HAProxy waits for combined certificates and step-ca
      haproxy = {
        after = [
          "haproxy-cert-combine.service"
          "container@step-ca.service"
        ];
        wants = [
          "haproxy-cert-combine.service"
          "container@step-ca.service"
        ];
      };

      # Base domain ACME waits for DNS
      "acme-${config.hostSpec.domain}" = {
        after = [ "cloudflare-dyndns.service" ];
        wants = [ "cloudflare-dyndns.service" ];
      };
    }

    # Service domain ACME certificates wait for DNS
    (lib.mapAttrs' (
      name: cfg:
      lib.nameValuePair "acme-${cfg.domain}" {
        after = [ "cloudflare-dyndns.service" ];
        wants = [ "cloudflare-dyndns.service" ];
      }
    ) allDomains)
  ];

  # ACME configuration - dynamically generate certificates for all configured domains
  security.acme = {
    acceptTerms = true;
    defaults = {
      email = config.hostSpec.services.acme.email;
      dnsProvider = config.hostSpec.services.acme.dnsProvider;
      dnsPropagationCheck = true;
      group = "haproxy";
      keyType = "ec256";
      dnsResolver = "1.1.1.1:53";
    };

    # Dynamically generate certificates for base domain and all service domains
    certs = lib.mkMerge [
      # Base domain certificate
      {
        "${config.hostSpec.domain}" = {
          domain = config.hostSpec.domain;
          environmentFile = config.sops.secrets."cloudflare/acme-env".path;
          webroot = null;
        };
      }
      # Service domain certificates
      (lib.mapAttrs' (
        name: cfg:
        lib.nameValuePair cfg.domain {
          domain = cfg.domain;
          environmentFile = config.sops.secrets."cloudflare/acme-env".path;
          webroot = null;
        }
      ) allDomains)
    ];
  };
}
