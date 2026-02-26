# Netbird mesh VPN server (management + signal)
# Proxied through HAProxy with mTLS, OIDC via Kanidm
# No coturn — declarative config only
{
  config,
  lib,
  inputs,
  pkgs,
  ...
}:
let
  cfg = config.custom.services.netbird;
  authDomain = config.custom.reverseProxy.virtualHosts.auth.domain;
  sopsFolder = builtins.toString inputs.nix-secrets + "/sops";
  dashboardPort = 18081;
  dashboardEnabled = cfg.dashboard.enable || config.services.netbird.server.dashboard.enable;
  # OIDC workaround overview (enableTokenProxy = true):
  # 1) Discovery is served from netbird.* but points auth + jwks to auth.*
  # 2) Browser auth happens on auth.* (mTLS enforced).
  # 3) App receives the auth code via localhost redirect.
  # 4) App posts code + PKCE verifier to netbird.* /oauth2/token (no mTLS).
  # 5) HAProxy proxies token exchange to Kanidm.
  oidcDiscoveryJson = builtins.toJSON {
    issuer = "https://${authDomain}/oauth2/openid/netbird";
    authorization_endpoint = "https://${authDomain}/ui/oauth2";
    token_endpoint = "https://${cfg.domain}/oauth2/token";
    jwks_uri = "https://${authDomain}/oauth2/openid/netbird/public_key.jwk";
  };
in
{
  options.custom.services.netbird = {
    enable = lib.mkEnableOption "Netbird mesh VPN server with Kanidm OIDC";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "netbird.${config.hostSpec.domain}";
      description = "FQDN for the Netbird server";
    };
    enableTokenProxy = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Serve custom OIDC discovery + proxy /oauth2/token via the Netbird domain (workaround for clients without mTLS support)";
    };
    dashboard = {
      enable = lib.mkEnableOption "Netbird admin dashboard";
      domain = lib.mkOption {
        type = lib.types.str;
        default = "netbird-admin.${config.hostSpec.domain}";
        description = "FQDN for the Netbird dashboard";
      };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      # Backup NetBird management DBs to SnapRAID storage (safe for cold backups)
      systemd.services.netbird-mgmt-backup = {
        description = "NetBird management DB backup";
        serviceConfig = {
          Type = "oneshot";
        };
        path = [ pkgs.coreutils pkgs.sqlite ];
        script = ''
          set -euo pipefail
          backup_dir="/mnt/storage/netbird/backups"
          ts="$(date -u +%Y%m%d-%H%M%S)"

          mkdir -p "$backup_dir"

          if [ -f /var/lib/netbird-mgmt/data/store.db ]; then
            sqlite3 /var/lib/netbird-mgmt/data/store.db ".backup '$backup_dir/store-$ts.db'"
          fi

          if [ -f /var/lib/netbird-mgmt/data/events.db ]; then
            sqlite3 /var/lib/netbird-mgmt/data/events.db ".backup '$backup_dir/events-$ts.db'"
          fi

          if [ -f /var/lib/netbird-mgmt/management.json ]; then
            cp /var/lib/netbird-mgmt/management.json "$backup_dir/management-$ts.json"
          fi

          # Keep 14 days of backups
          find "$backup_dir" -type f -name 'store-*.db' -mtime +14 -delete
          find "$backup_dir" -type f -name 'events-*.db' -mtime +14 -delete
          find "$backup_dir" -type f -name 'management-*.json' -mtime +14 -delete
        '';
      };

      systemd.timers.netbird-mgmt-backup = {
        description = "Daily NetBird management DB backup";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
          RandomizedDelaySec = "30m";
        };
      };

      systemd.tmpfiles.rules = [
        "d /mnt/storage/netbird/backups 0755 root root -"
      ];

      services.netbird.server = {
        enable = true;
        domain = cfg.domain;
        enableNginx = false; # HAProxy handles reverse proxying

        management = {
          oidcConfigEndpoint =
            if cfg.enableTokenProxy then
              "https://${cfg.domain}/oauth2/openid/netbird/.well-known/openid-configuration"
            else
              "https://${authDomain}/oauth2/openid/netbird/.well-known/openid-configuration";
          logLevel = "INFO";
          turnDomain = cfg.domain; # Required by module; overridden in settings below
          singleAccountModeDomain = config.hostSpec.domain;
          dnsDomain = "netbird.selfhosted";
          disableAnonymousMetrics = true;

          settings = {
            DataStoreEncryptionKey._secret = config.sops.secrets."netbird/datastore-encryption-key".path;

            Stuns = [
              {
                Proto = "udp";
                URI = "stun:stun.l.google.com:19302";
                Username = "";
                Password = null;
              }
            ];
            # TODO: Self-host coturn on this host (3478/udp + 5349/tcp) with a small relay range and
            # SOPS-backed credentials to avoid relying on Google's public STUN.

            TURNConfig = {
              Turns = [ ];
              TimeBasedCredentials = false;
              Secret = "unused";
            };

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

            PKCEAuthorizationFlow.ProviderConfig = {
              Audience = "netbird";
              ClientID = "netbird";
              ClientSecret = "";
              AuthorizationEndpoint = "https://${authDomain}/oauth2/authorize";
              Scope = "openid profile email offline_access";
              RedirectURLs = [ "http://localhost:53000" ];
              UseIDToken = false;
            }
            // lib.optionalAttrs cfg.enableTokenProxy {
              TokenEndpoint = "https://${cfg.domain}/oauth2/token";
            };

            IdpManagerConfig.ManagerType = "none";
          };
        };

        signal = { };

        coturn.enable = false;
      };

      # NetBird client on the server (declarative enrollment via setup key)
      services.netbird.clients.server = {
        port = 51820;
        interface = "nb-server";
        logLevel = "info";
        config = {
          ManagementURL = {
            Scheme = "https";
            Host = "${cfg.domain}:443";
          };
        };
        login.enable = true;
        login.setupKeyFile = config.sops.secrets."netbird/setup-key".path;
        # Find the store path for netbird-server:
        #   readlink -f /run/current-system/sw/bin/netbird-server
        # Show status:
        #   /nix/store/<...>-netbird-client-<...>-wrapper-server/bin/netbird-server status
      };

      custom.reverseProxy.virtualHosts.netbird = {
        domain = cfg.domain;
        backendHost = "127.0.0.1";
        backendPort = config.services.netbird.server.management.port;
        backendSSL = false;
        backendH2 = true;
        mTLS = false; # Netbird clients can't present step-ca certs
        extraBackends =
          {
            # Keep signal routing even when token proxy backends are enabled.
            signal = {
              pathPrefix = "/signalexchange.SignalExchange/";
              backendHost = "127.0.0.1";
              backendPort = config.services.netbird.server.signal.port;
            };
          }
          // lib.optionalAttrs cfg.enableTokenProxy {
            oidcToken = {
              pathPrefix = "/oauth2/token";
              backendHost = config.custom.reverseProxy.virtualHosts.auth.backendHost;
              backendPort = config.custom.reverseProxy.virtualHosts.auth.backendPort;
              backendSSL = true;
              backendSNI = config.custom.reverseProxy.virtualHosts.auth.domain;
              hostHeader = config.custom.reverseProxy.virtualHosts.auth.domain;
              allowMethods = [ "POST" ];
            };
          };
        oidcDiscovery = lib.mkIf cfg.enableTokenProxy {
          path = "/oauth2/openid/netbird/.well-known/openid-configuration";
          json = oidcDiscoveryJson;
        };
      };

      services.netbird.server.dashboard = lib.mkMerge [
        (lib.mkIf cfg.dashboard.enable {
          enable = true;
          enableNginx = true;
          domain = cfg.dashboard.domain;
          managementServer = "https://${cfg.domain}";
        })
        (lib.mkIf dashboardEnabled {
          settings = {
            AUTH_AUTHORITY = lib.mkDefault (
              if cfg.enableTokenProxy then
                "https://${cfg.domain}/oauth2/openid/netbird"
              else
                "https://${authDomain}/oauth2/openid/netbird"
            );
            # Dashboard prepends its own origin, so use relative paths here.
            AUTH_REDIRECT_URI = lib.mkDefault "/oauth2/token";
            AUTH_SILENT_REDIRECT_URI = lib.mkDefault "/silent-renew.html";
            NETBIRD_TOKEN_SOURCE = lib.mkForce "idToken";
          };
        })
      ];

      services.nginx.virtualHosts = lib.mkIf cfg.dashboard.enable {
        "${cfg.dashboard.domain}" = {
          listen = [
            {
              addr = "127.0.0.1";
              port = dashboardPort;
            }
          ];
          locations."/".tryFiles = lib.mkForce "$uri $uri.html /index.html";
        };
      };

      custom.reverseProxy.virtualHosts.netbirdDashboard = lib.mkIf cfg.dashboard.enable {
        domain = cfg.dashboard.domain;
        backendHost = "127.0.0.1";
        backendPort = dashboardPort;
        backendSSL = false;
        backendH2 = false;
        mTLS = true;
      };

      custom.kanidm.oauthClients.netbird = {
        displayName = "Netbird VPN";
        public = true;
        originUrl = [
          "https://${cfg.domain}/api/auth/callback"
          "https://${cfg.dashboard.domain}/"
          "https://${cfg.dashboard.domain}/oauth2/token"
          "https://${cfg.dashboard.domain}/silent-renew.html"
          "http://localhost:53000"
        ];
        originLanding = "https://${cfg.domain}/";
        scopeMap.netbird_users = [
          "openid"
          "email"
          "profile"
          "offline_access"
        ];
      };

      sops.secrets."netbird/datastore-encryption-key" = {
        sopsFile = "${sopsFolder}/${config.hostSpec.hostName}.yaml";
        owner = "root";
        group = "root";
        mode = "0400";
      };

      sops.secrets."netbird/setup-key" = {
        sopsFile = "${sopsFolder}/${config.hostSpec.hostName}.yaml";
        owner = "root";
        group = "root";
        mode = "0400";
      };
    }
  ]);
}
