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

    managementTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to a file containing a Netbird Personal Access Token for provisioning.";
    };

    setupKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to the setup key file to ensure exists in the database.";
    };

    staticIPs = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Map of peer names to desired static Netbird IPs.";
    };

    nameservers = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption { type = lib.types.str; };
            ip = lib.mkOption { type = lib.types.str; };
            domains = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ config.hostSpec.domain ]; # Default to the host domain
            };
            primary = lib.mkOption {
              type = lib.types.bool;
              default = true;
            };
          };
        }
      );
      default = [ ];
      description = "List of nameservers to provision in the Netbird network.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        # Backup NetBird management DBs to SnapRAID storage
        systemd.services.netbird-mgmt-backup = {
          description = "NetBird management DB backup";
          serviceConfig = {
            Type = "oneshot";
          };
          path = [
            pkgs.coreutils
            pkgs.sqlite
          ];
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
              TURNConfig = {
                Turns = lib.mkForce [
                  {
                    Proto = "udp";
                    URI = "turn:${cfg.domain}:3478";
                    Username = "netbird";
                    Password = {
                      _secret = config.sops.secrets."netbird/turn-password".path;
                    };
                  }
                  {
                    Proto = "tcp";
                    URI = "turn:${cfg.domain}:3478";
                    Username = "netbird";
                    Password = {
                      _secret = config.sops.secrets."netbird/turn-password".path;
                    };
                  }
                ];
                TimeBasedCredentials = false;
                Secret = "";
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
                Scope = "openid profile email offline_access api";
                RedirectURLs = [ "http://localhost:53000" ];
                UseIDToken = false;
              }
              // lib.optionalAttrs cfg.enableTokenProxy {
                TokenEndpoint = "https://${cfg.domain}/oauth2/token";
              };

              IdpManagerConfig.ManagerType = "none";

              PATConfig = {
                Enabled = true;
              };
            };
          };

          signal = { };

          coturn = {
            enable = true;
            domain = cfg.domain;
            user = "netbird";
            passwordFile = config.sops.secrets."netbird/turn-password".path;
            useAcmeCertificates = false;
          };
        };

        services.coturn = {
          no-tls = true;
          no-dtls = true;
          min-port = 49160;
          max-port = 49200;
        };

        custom.reverseProxy.virtualHosts.netbird = {
          domain = cfg.domain;
          backendHost = "127.0.0.1";
          backendPort = config.services.netbird.server.management.port;
          backendSSL = false;
          backendH2 = true;
          # Netbird clients can't present step-ca certs
          # But this is fine because authentication is gated behind mTLS
          mTLS = false;
          extraBackends = {
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
            "api"
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

        sops.secrets."netbird/turn-password" = {
          sopsFile = "${sopsFolder}/${config.hostSpec.hostName}.yaml";
          owner = "root";
          group = "turnserver";
          mode = "0440";
        };
      }
      # Provisioning Service
      {
        systemd.services.netbird-provisioning = {
          description = "Declarative provisioning for Netbird Management (SQLite)";
          after = [ "netbird-management.service" ];
          wantedBy = [ "multi-user.target" ];

          path = with pkgs; [
            sqlite
            jq
            coreutils
          ];

          script = ''
            DB="/var/lib/netbird-mgmt/data/store.db"
            
            # 0. Provision Setup Key
            ${lib.optionalString (cfg.setupKeyFile != null) ''
              SETUP_KEY=$(cat ${cfg.setupKeyFile})
              # Check if key already exists
              KEY_EXISTS=$(sqlite3 "$DB" "SELECT 1 FROM setup_keys WHERE key = '$SETUP_KEY' LIMIT 1;")
              if [ -z "$KEY_EXISTS" ]; then
                echo "Injecting SOPS setup-key into database..."
                ACCOUNT_ID=$(sqlite3 "$DB" "SELECT id FROM accounts LIMIT 1;")
                NEW_KEY_ID=$(cat /proc/sys/kernel/random/uuid | tr -d '-')
                # Insert reusable, non-expiring setup key associated with the first account
                sqlite3 "$DB" "INSERT INTO setup_keys (id, account_id, key, name, type, created_at, expires_at, usage_limit, used_times, ephemeral, last_used, auto_groups) \
                  VALUES ('$NEW_KEY_ID', '$ACCOUNT_ID', '$SETUP_KEY', 'Managed by SOPS', 'reusable', datetime('now'), datetime('now', '+10 years'), 0, 0, 0, NULL, '[\"all\"]');"
              fi
            ''}

            # 1. Provision Static IPs
            echo "Syncing Static IPs via SQLite..."
            ${lib.concatStringsSep "\n" (
              lib.mapAttrsToList (name: ip: ''
                echo "Deduplicating and ensuring peer ${name} has IP ${ip}..."
                # Find the ID of the most recently seen peer with this name
                LATEST_ID=$(sqlite3 "$DB" "SELECT id FROM peers WHERE name = '${name}' ORDER BY peer_status_last_seen DESC LIMIT 1;")
                if [ -n "$LATEST_ID" ]; then
                  # Delete all other entries with this name to avoid IP conflicts
                  sqlite3 "$DB" "DELETE FROM peers WHERE name = '${name}' AND id != '$LATEST_ID';"
                  # Update the IP of the remaining peer
                  sqlite3 "$DB" "UPDATE peers SET ip = '\"${ip}\"' WHERE id = '$LATEST_ID';"
                fi
              '') cfg.staticIPs
            )}

            # 2. Provision Nameservers
            # We fetch the first account_id to associate the nameserver
            ACCOUNT_ID=$(sqlite3 "$DB" "SELECT id FROM accounts LIMIT 1;")
            ALL_GROUP_ID=$(sqlite3 "$DB" "SELECT id FROM groups WHERE name = 'All' AND account_id = '$ACCOUNT_ID' LIMIT 1;")

            echo "Syncing Nameservers via SQLite (Account: $ACCOUNT_ID, Group: $ALL_GROUP_ID)..."
            ${lib.concatMapStringsSep "\n" (ns: ''
              NS_ID=$(sqlite3 "$DB" "SELECT id FROM name_server_groups WHERE name = '${ns.name}' LIMIT 1;")
              
              # Construct JSON fields
              NS_SERVERS_JSON='[{"ip":"${ns.ip}","ns_type":"udp","port":53}]'
              GROUPS_JSON='["'$ALL_GROUP_ID'"]'
              DOMAINS_JSON='${builtins.toJSON ns.domains}'

              if [ -n "$NS_ID" ]; then
                echo "Updating nameserver ${ns.name} ($NS_ID) with domains $DOMAINS_JSON..."
                sqlite3 "$DB" "UPDATE name_server_groups SET name_servers = '$NS_SERVERS_JSON', groups = '$GROUPS_JSON', \`primary\` = ${if ns.primary then "1" else "0"}, domains = '$DOMAINS_JSON', enabled = 1 WHERE id = '$NS_ID';"
              else
                NEW_ID=$(cat /proc/sys/kernel/random/uuid | tr -d '-')
                echo "Creating nameserver ${ns.name} ($NEW_ID) with domains $DOMAINS_JSON..."
                sqlite3 "$DB" "INSERT INTO name_server_groups (id, account_id, name, description, name_servers, groups, \`primary\`, domains, enabled, search_domains_enabled) \
                  VALUES ('$NEW_ID', '$ACCOUNT_ID', '${ns.name}', 'Managed by NixOS', '$NS_SERVERS_JSON', '$GROUPS_JSON', ${if ns.primary then "1" else "0"}, '$DOMAINS_JSON', 1, 1);"
              fi
            '') cfg.nameservers}
            
            # Restart management to pick up DB changes
            # (Netbird caches much of the DB in memory)
            if [ "$(systemctl is-active netbird-management.service)" == "active" ]; then
               echo "Restarting Netbird Management to reload database..."
               # Give SQLite a moment to sync to disk
               sleep 2
               systemctl restart netbird-management.service
            fi
          '';

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "root";
          };
        };
      }
    ]
  );
}
