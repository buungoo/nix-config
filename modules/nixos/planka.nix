{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  cfg = config.custom.services.planka;
  net = lib.custom.mkContainerNetworkConfig config cfg.network "planka";

  uid = toString cfg.uid;
  gid = toString cfg.gid;

  sopsFolder = builtins.toString inputs.nix-secrets + "/sops";

  authDomain = config.custom.reverseProxy.virtualHosts.auth.domain or "auth.${config.hostSpec.domain}";
in
{
  options.custom.services.planka = {
    enable = lib.mkEnableOption "Planka Kanban board (with Kanidm OIDC)";

    uid = lib.mkOption {
      type = lib.types.int;
      default = 11100;
      description = "UID for planka user on both host and container";
    };

    gid = lib.mkOption {
      type = lib.types.int;
      default = 11100;
      description = "GID for planka group on both host and container";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "planka.${config.hostSpec.domain}";
      description = "FQDN for the Planka reverse proxy virtual host";
    };

    network = lib.mkOption {
      type = lib.types.str;
      default = "planka";
      description = "Which containerNetwork to place planka on";
    };

    hostOctet = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = "Host octet for the container IP in the network subnet";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 1337;
      description = "Internal port the planka server listens on";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/planka";
      description = ''
        Host path for all persistent planka state — app data, uploads, and
        the PostgreSQL database (stored at $dataDir/postgresql inside).
      '';
    };

    oidcEnforced = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Force OIDC-only login (disables local password login). Useful once
        you have at least one OIDC user provisioned, since Planka has no
        offline password recovery flow if the only admin can't get back in.
      '';
    };

    oidcAdminGroup = lib.mkOption {
      type = lib.types.str;
      default = "planka_admins";
      description = ''
        Kanidm group whose members should be Planka admins. The group is
        mapped to the `admin` role via OIDC_ADMIN_ROLES.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.custom.mkContainerServiceConfig "planka" { })
      {
        # Host-side user (matches container UID/GID for bindmount permissions)
        users.users.planka = {
          isSystemUser = true;
          group = "planka";
          uid = cfg.uid;
        };
        users.groups.planka.gid = cfg.gid;

        # Reverse proxy
        custom.reverseProxy.virtualHosts.planka = {
          domain = cfg.domain;
          backendHost = net.containerIP;
          backendPort = cfg.port;
          backendSSL = false;
        };

        # Container network
        hostSpec.networking.containerNetworks.${cfg.network} = {
          bridge = lib.mkDefault "${cfg.network}-bridge";
          subnet = lib.mkDefault "10.0.4.0/24";
          gateway = lib.mkDefault "10.0.4.1";
          containers.planka = lib.mkDefault cfg.hostOctet;
        };

        # Persistent data dir (app data + postgres subdir + logs; owned by planka uid/gid)
        systemd.tmpfiles.rules = [
          "d ${cfg.dataDir} 0750 ${uid} ${gid} -"
          "d ${cfg.dataDir}/postgresql 0700 ${uid} ${gid} -"
          "d ${cfg.dataDir}/logs 0750 ${uid} ${gid} -"
        ];

        # Sops secrets (read by root via LoadCredential, then handed to the
        # unprivileged planka service via $CREDENTIALS_DIRECTORY)
        sops.secrets."planka/secret-key" = {
          sopsFile = "${sopsFolder}/${config.hostSpec.hostName}.yaml";
          owner = "root";
          group = "root";
          mode = "0400";
        };
        sops.secrets."planka/oidc-client-secret" = {
          sopsFile = "${sopsFolder}/${config.hostSpec.hostName}.yaml";
          owner = "root";
          group = "kanidm";
          mode = "0440";
        };

        # Kanidm OAuth2 client
        # Planka redirects to <BASE_URL>/oidc-callback after auth (see
        # server/config/custom.js:oidcRedirectUri).
        custom.kanidm.oauthClients.planka = {
          displayName = "Planka";
          originUrl = [ "https://${cfg.domain}/oidc-callback" ];
          originLanding = "https://${cfg.domain}/";
          secretFile = config.sops.secrets."planka/oidc-client-secret".path;
          # Planka v2.1.1 doesn't implement PKCE (no code_challenge sent in
          # the authorise request). Kanidm enforces PKCE by default; disable
          # for this confidential client only — the client secret still
          # protects the token exchange.
          allowInsecureClientDisablePkce = true;
          # Planka's openid-client defaults to RS256 for ID token signing;
          # Kanidm defaults to ES256. Switch this client to RS256.
          enableLegacyCrypto = true;
          # Both groups grant auth scopes so admins only need planka_admins
          # membership (no need to also be in planka_users). OIDC_ADMIN_ROLES
          # on the planka side decides admin vs regular role.
          scopeMap.planka_users = [
            "openid"
            "email"
            "profile"
          ];
          scopeMap.${cfg.oidcAdminGroup} = [
            "openid"
            "email"
            "profile"
          ];
          # Emit a `groups` claim in the userinfo response so Planka can
          # apply OIDC_ADMIN_ROLES based on group membership. Without this,
          # Kanidm sends no group info and every user lands as the default
          # role — including the first admin needed to bootstrap the instance.
          claimMap.groups = {
            joinType = "array";
            valuesByGroup.${cfg.oidcAdminGroup} = [ cfg.oidcAdminGroup ];
            valuesByGroup.planka_users = [ "planka_users" ];
          };
        };

        # Container
        containers.planka = {
          autoStart = true;
          ephemeral = true;

          bindMounts = {
            "/var/lib/planka" = {
              hostPath = cfg.dataDir;
              isReadOnly = false;
            };
            "/run/secrets" = {
              hostPath = "/run/secrets";
              isReadOnly = true;
            };
          };

          privateNetwork = true;
          hostBridge = net.bridge;
          localAddress = "${net.containerIP}/${net.cidr}";

          forwardPorts = [
            {
              hostPort = cfg.port;
              containerPort = cfg.port;
            }
          ];

          config = lib.mkMerge [
            (lib.custom.mkContainerBaseConfig (
              net // { inherit (config.hostSpec) stateVersion; }
            ))
            {
              # PostgreSQL — data lives under the planka data bindmount so all
              # persistent state goes through one host path (/var/lib/planka).
              # Runs as the planka user so ownership matches across the
              # host/container bindmount.
              services.postgresql = {
                enable = true;
                dataDir = "/var/lib/planka/postgresql";
                ensureDatabases = [ "planka" ];
                ensureUsers = [
                  {
                    name = "planka";
                    ensureDBOwnership = true;
                  }
                ];
                # planka's knex/pg client doesn't honor the `?host=/socket`
                # query param and falls back to TCP ::1. Postgres on
                # local-only TCP inside the isolated container is safe to
                # trust-auth; nothing outside the container can reach it.
                authentication = lib.mkForce ''
                  local all all              trust
                  host  all all 127.0.0.1/32 trust
                  host  all all ::1/128      trust
                '';
              };
              systemd.services.postgresql.serviceConfig = {
                User = lib.mkForce "planka";
                Group = lib.mkForce "planka";
              };
              systemd.tmpfiles.rules = [
                "d /run/postgresql 0755 planka planka -"
              ];

              # Planka service
              systemd.services.planka = {
                description = "Planka Kanban board";
                wantedBy = [ "multi-user.target" ];
                after = [
                  "network.target"
                  "postgresql.service"
                ];
                requires = [ "postgresql.service" ];

                environment = {
                  BASE_URL = "https://${cfg.domain}";
                  # TCP localhost — postgres is local-only inside the container
                  # and trust-auth'd for 127.0.0.1 / ::1 (see services.postgresql
                  # authentication block below).
                  DATABASE_URL = "postgresql://planka@127.0.0.1/planka";

                  # SECRET__FILE env vars are read by start.sh, which runs as the
                  # planka user. The sops files on /run/secrets are root:* and
                  # planka can't read them directly, so systemd's LoadCredential
                  # (below) pre-stages them into $CREDENTIALS_DIRECTORY where
                  # only the unit's user can read.
                  SECRET_KEY__FILE = "%d/secret-key";
                  OIDC_CLIENT_SECRET__FILE = "%d/oidc-client-secret";

                  TRUST_PROXY = "true";
                  LOG_LEVEL = "silly";
                  # Server keeps socket.io at the default /socket.io path;
                  # HAProxy rewrites incoming /engine.io/* (which is what
                  # planka's sails.io.js client unfortunately sends due to
                  # engine.io-client default leaking through) → /socket.io/*.
                  sails_log__level = "verbose";
                  # Planka's winston file transport defaults to
                  # `${process.cwd()}/logs/planka.log` — cwd is the read-only
                  # nix store path (set by the wrapper's --chdir, needed so
                  # sails.js finds its config). Redirect file logs to the
                  # writable bindmount.
                  LOG_FILE = "/var/lib/planka/logs/planka.log";

                  # OIDC integration with Kanidm
                  OIDC_ISSUER = "https://${authDomain}/oauth2/openid/planka";
                  OIDC_CLIENT_ID = "planka";
                  OIDC_SCOPES = "openid email profile";
                  OIDC_EMAIL_ATTRIBUTE = "email";
                  OIDC_NAME_ATTRIBUTE = "name";
                  OIDC_USERNAME_ATTRIBUTE = "preferred_username";
                  OIDC_ROLES_ATTRIBUTE = "groups";
                  OIDC_ADMIN_ROLES = cfg.oidcAdminGroup;
                  OIDC_ENFORCED = if cfg.oidcEnforced then "true" else "false";

                  # No outgoing-proxy filtering — let planka talk to the
                  # network directly (skips the embedded squid).
                  OUTGOING_BLOCKED_HOSTS = "";
                };

                serviceConfig = {
                  Type = "simple";
                  User = "planka";
                  Group = "planka";
                  ExecStart = lib.getExe pkgs.planka;
                  WorkingDirectory = "/var/lib/planka";
                  Restart = "on-failure";
                  RestartSec = "5s";
                  # systemd reads these as root and stages them in
                  # $CREDENTIALS_DIRECTORY (referenced as %d above), readable
                  # only by the service user — same pattern as immich's
                  # _secret templating, just via systemd-credentials.
                  LoadCredential = [
                    "secret-key:/run/secrets/planka/secret-key"
                    "oidc-client-secret:/run/secrets/planka/oidc-client-secret"
                  ];
                  # Hardening
                  NoNewPrivileges = true;
                  ProtectSystem = "strict";
                  ProtectHome = true;
                  PrivateTmp = true;
                  ReadWritePaths = [ "/var/lib/planka" ];
                };
              };

              # Container user
              users.users.planka = {
                isSystemUser = true;
                group = "planka";
                uid = cfg.uid;
                home = "/var/lib/planka";
                createHome = true;
              };
              users.groups.planka.gid = cfg.gid;

              networking.firewall.allowedTCPPorts = [ cfg.port ];
            }
          ];
        };
      }
    ]
  );
}
