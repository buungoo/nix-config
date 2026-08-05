# First-run note: Tandoor's index view redirects to /setup/ when no users
# exist, and that page only offers local-password signup (no Kanidm button).
# /accounts/login/ also funnels through the same redirect, so neither UI path
# lets you start as the OIDC user. To make the Kanidm identity the superuser
# instead, kick the OAuth flow directly:
#   https://<domain>/accounts/oidc/kanidm/login/?process=login
# allauth provisions a regular user on first login; then promote it from the
# host with:
#   sudo machinectl shell tandoor /run/current-system/sw/bin/bash -c \
#     "psql -U tandoor_recipes -d tandoor_recipes -c \"UPDATE auth_user SET is_superuser = true, is_staff = true WHERE id = 1; SELECT id, username, is_superuser, is_staff FROM auth_user;\""
{
  config,
  lib,
  inputs,
  ...
}:
let
  cfg = config.custom.services.tandoor;
  net = lib.custom.mkContainerNetworkConfig config cfg.network "tandoor";

  uid = toString cfg.uid;
  gid = toString cfg.gid;

  sopsFolder = builtins.toString inputs.nix-secrets + "/sops";
  authDomain = config.custom.reverseProxy.virtualHosts.auth.domain or "auth.${config.hostSpec.domain}";
in
{
  options.custom.services.tandoor = {
    enable = lib.mkEnableOption "Tandoor Recipes container (with Kanidm OIDC)";

    uid = lib.mkOption {
      type = lib.types.int;
      default = 11200;
      description = "UID for the Tandoor user on both host and container";
    };

    gid = lib.mkOption {
      type = lib.types.int;
      default = 11200;
      description = "GID for the Tandoor group on both host and container";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "tandoor.${config.hostSpec.domain}";
      description = "FQDN for the Tandoor reverse proxy virtual host";
    };

    network = lib.mkOption {
      type = lib.types.str;
      default = "tandoor";
      description = "Which containerNetwork to place Tandoor on";
    };

    hostOctet = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = "Host octet for the container IP in the network subnet";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8085;
      description = "Internal port the Tandoor server listens on";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/tandoor-recipes";
      description = "Host path for persistent Tandoor application data";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.custom.mkContainerServiceConfig "tandoor" { })
      {
        users.users.tandoor_recipes = {
          isSystemUser = true;
          group = "tandoor_recipes";
          uid = cfg.uid;
        };
        users.groups.tandoor_recipes.gid = cfg.gid;

        custom.reverseProxy.virtualHosts.tandoor = {
          domain = cfg.domain;
          backendHost = net.containerIP;
          backendPort = cfg.port;
          backendSSL = false;
        };

        hostSpec.networking.containerNetworks.${cfg.network} = {
          bridge = lib.mkDefault "${cfg.network}-bridge";
          subnet = lib.mkDefault "10.0.5.0/24";
          gateway = lib.mkDefault "10.0.5.1";
          containers.tandoor = lib.mkDefault cfg.hostOctet;
        };

        systemd.tmpfiles.rules = [
          "d ${cfg.dataDir} 0750 ${uid} ${gid} -"
          "d ${cfg.dataDir}/media 0750 ${uid} ${gid} -"
          "d ${cfg.dataDir}/postgresql 0700 ${uid} ${gid} -"
        ];

        sops.secrets."tandoor/secret-key" = {
          sopsFile = "${sopsFolder}/${config.hostSpec.hostName}.yaml";
          owner = "tandoor_recipes";
          group = "tandoor_recipes";
          mode = "0400";
        };
        sops.secrets."tandoor/oidc-client-secret" = {
          sopsFile = "${sopsFolder}/${config.hostSpec.hostName}.yaml";
          owner = "tandoor_recipes";
          group = "kanidm";
          mode = "0440";
        };
        # systemd EnvironmentFile-format. Value is a Python dict literal
        # (Tandoor parses SOCIALACCOUNT_PROVIDERS with ast.literal_eval, not
        # json.loads — so True must be capitalized and dict-literal syntax is
        # required). Rendered to /run/secrets/rendered/... by sops-nix; the
        # OIDC secret never lands in the Nix store.
        sops.templates."tandoor-socialaccount-providers" = {
          owner = "tandoor_recipes";
          group = "tandoor_recipes";
          mode = "0400";
          content = ''
            SOCIALACCOUNT_PROVIDERS={'openid_connect': {'OAUTH_PKCE_ENABLED': True, 'APPS': [{'provider_id': 'kanidm', 'name': 'Kanidm', 'client_id': 'tandoor', 'secret': '${config.sops.placeholder."tandoor/oidc-client-secret"}', 'settings': {'server_url': 'https://${authDomain}/oauth2/openid/tandoor'}}]}}
          '';
        };

        custom.kanidm.oauthClients.tandoor = {
          displayName = "Tandoor Recipes";
          originUrl = [ "https://${cfg.domain}/accounts/oidc/kanidm/login/callback/" ];
          originLanding = "https://${cfg.domain}/";
          secretFile = config.sops.secrets."tandoor/oidc-client-secret".path;
          scopeMap.tandoor_users = [
            "openid"
            "email"
            "profile"
          ];
        };

        containers.tandoor = {
          autoStart = true;
          ephemeral = false;

          bindMounts = {
            "/var/lib/tandoor-recipes" = {
              hostPath = cfg.dataDir;
              isReadOnly = false;
            };
            "/run/secrets" = {
              hostPath = "/run/secrets";
              isReadOnly = true;
            };
            "/run/tandoor-socialaccount-providers.env" = {
              hostPath = config.sops.templates."tandoor-socialaccount-providers".path;
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
              # Postgres data lives under the tandoor bindmount so all
              # persistent state goes through one host path
              # (/var/lib/tandoor-recipes). Runs as the tandoor_recipes
              # user so ownership matches across the host/container
              # bindmount; trust-auth on local-only socket is safe inside
              # the isolated container.
              services.postgresql = {
                dataDir = "/var/lib/tandoor-recipes/postgresql";
                authentication = lib.mkForce ''
                  local all all              trust
                  host  all all 127.0.0.1/32 trust
                  host  all all ::1/128      trust
                '';
              };
              systemd.services.postgresql.serviceConfig = {
                User = lib.mkForce "tandoor_recipes";
                Group = lib.mkForce "tandoor_recipes";
              };
              systemd.tmpfiles.rules = [
                "d /run/postgresql 0755 tandoor_recipes tandoor_recipes -"
              ];

              services.tandoor-recipes = {
                enable = true;
                address = net.containerIP;
                port = cfg.port;
                database.createLocally = true;
                extraConfig = {
                  ALLOWED_HOSTS = cfg.domain;
                  CSRF_TRUSTED_ORIGINS = "https://${cfg.domain}";
                  MEDIA_ROOT = "/var/lib/tandoor-recipes/media";
                  SECRET_KEY_FILE = "/run/secrets/tandoor/secret-key";
                  # Adds allauth.socialaccount.providers.openid_connect to
                  # INSTALLED_APPS — without this, the OIDC URL routes aren't
                  # registered and no SSO button renders on the login page.
                  SOCIAL_PROVIDERS = "allauth.socialaccount.providers.openid_connect";
                };
              };

              # SOCIALACCOUNT_PROVIDERS is injected via EnvironmentFile (not
              # extraConfig) so the OIDC client secret stays out of the
              # Nix-store-backed systemd unit. systemd reads this file at
              # unit start as root and exposes the var to the process.
              systemd.services.tandoor-recipes.serviceConfig.EnvironmentFile = [
                "/run/tandoor-socialaccount-providers.env"
              ];

              systemd.services.tandoor-recipes.serviceConfig.BindReadOnlyPaths = [
                "/run/secrets/tandoor/secret-key"
                "/run/tandoor-socialaccount-providers.env"
              ];

              users.users.tandoor_recipes.uid = cfg.uid;
              users.groups.tandoor_recipes.gid = cfg.gid;

              networking.firewall.allowedTCPPorts = [ cfg.port ];
            }
          ];
        };
      }
    ]
  );
}
