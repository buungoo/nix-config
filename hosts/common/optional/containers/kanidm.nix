# By default, this container has no shell for security
# To enable shell access: Set enableShellAccess = true in the let block below,
# then rebuild: sudo nixos-rebuild switch
#
# Once enabled, login as root:
# sudo nixos-container root-login kanidm
# Or login as kanidm user:
# sudo systemd-run -t --pty -M kanidm --uid=kanidm /run/current-system/sw/bin/bash
#
# Kanidm commands
# CLI login
# kanidm login -D <user>
# User onboarding
# kanidm person credential create-reset-token <user>
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  enableShellAccess = false;
in
{
  imports = [
    (./networking.nix)
  ];

  # Create kanidm user and group on host for SOPS secrets and consistency
  users.users.kanidm = {
    isSystemUser = true;
    group = "kanidm";
    uid = 993;
  };
  users.groups.kanidm = {
    gid = 993;
  };

  # Domain configuration for this service
  hostSpec.domains.auth = {
    domain = "auth.${config.hostSpec.domain}";
    public = true;
    backendHost = "10.0.2.2";
    backendPort = 8443;
    backendSSL = true;
  };

  hostSpec.networking.containerNetworks.kanidm.bridge = lib.mkDefault "kanidm-bridge";
  hostSpec.networking.containerNetworks.kanidm.subnet = lib.mkDefault "10.0.2.0/24";
  hostSpec.networking.containerNetworks.kanidm.gateway = lib.mkDefault "10.0.2.1";
  hostSpec.networking.containerNetworks.kanidm.containers.kanidm = lib.mkDefault 2;

  containers.kanidm =
    let
      net = lib.custom.mkContainerNetworkConfig config "kanidm" "kanidm";
      kanidmData = "/var/lib/kanidm";
      hostConfig = config;
    in
    {
      autoStart = true;

      bindMounts = {
        # Kanidm data directory
        # Must be on real btrfs, not mergerfs, for SQLite database mmap support
        "${kanidmData}" = {
          hostPath = "/mnt/disks/data0/kanidm";
          isReadOnly = false;
        };
        # Mount ACME certificates
        "/etc/ssl/certs/kanidm" = {
          hostPath = hostConfig.security.acme.certs."${hostConfig.hostSpec.domains.auth.domain}".directory;
          isReadOnly = true;
        };
        # Mount SOPS secrets
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
          hostPort = 8443;
          containerPort = 8443;
        }
        {
          hostPort = 3636;
          containerPort = 3636;
        }
      ];

      config = lib.mkMerge [
        (lib.custom.mkContainerBaseConfig net)
        {
          # Make auth domain resolve to container's own IP inside container
          networking.hosts = {
            "${net.containerIP}" = [ hostConfig.hostSpec.domains.auth.domain ];
          };

          # Open firewall for Kanidm
          networking.firewall.allowedTCPPorts = [
            8443
            3636
          ];

          services.kanidm = {
            enableServer = true;
            enableClient = true;

            package = pkgs.kanidm.withSecretProvisioning;

            clientSettings = {
              uri = "https://${hostConfig.hostSpec.domains.auth.domain}:8443"; # Inside container, connect directly to Kanidm
              verify_ca = true;
              verify_hostnames = true;
              ca_path = "/etc/ssl/certs/kanidm/fullchain.pem";
            };

            serverSettings = {
              log_level = "info";

              domain = hostConfig.hostSpec.domains.auth.domain;
              origin = "https://${hostConfig.hostSpec.domains.auth.domain}";

              tls_chain = "/etc/ssl/certs/kanidm/fullchain.pem";
              tls_key = "/etc/ssl/certs/kanidm/key.pem";

              bindaddress = "0.0.0.0:8443";
              ldapbindaddress = "0.0.0.0:3636";

              # Trust the proxy headers from the host
              trust_x_forward_for = true;

              # auth_failure_ttl = 300;
              # auth_failure_count = 3;
            };

            provision = {
              enable = true;
              adminPasswordFile = hostConfig.sops.secrets."kanidm/admin-password".path;
              idmAdminPasswordFile = hostConfig.sops.secrets."kanidm/admin-password".path;

              # Create persons from hostSpec.services.kanidm.users
              persons = lib.mapAttrs (username: userConfig: {
                displayName = userConfig.displayName;
                mailAddresses = userConfig.mailAddresses;
              }) hostConfig.hostSpec.services.kanidm.users;

              # Create groups from hostSpec.services.kanidm.groups
              groups = lib.mapAttrs (groupName: groupConfig: {
                members = groupConfig.members;
              }) hostConfig.hostSpec.services.kanidm.groups;

              systems.oauth2.immich = {
                displayName = "Immich";
                originUrl = [
                  "https://${hostConfig.hostSpec.domains.immich.domain}/auth/login"
                  "https://${hostConfig.hostSpec.domains.immich.domain}/api/oauth/mobile-redirect"
                  "https://${hostConfig.hostSpec.domains.immich.domain}/user-settings"
                  "app.immich:///oauth-callback"
                  "app.immich://oauth-callback"
                  "app.immich:/oauth-callback"
                  "com.alextran.immich://oauth-callback"
                ];
                originLanding = "https://${hostConfig.hostSpec.domains.immich.domain}/";
                basicSecretFile = hostConfig.sops.secrets."immich/oidc-client-secret".path;
                enableLegacyCrypto = true; # Immich still uses RS256 instead of ES256
                preferShortUsername = true;

                scopeMaps.immich_users = [
                  "openid"
                  "email"
                  "profile"
                ];
              };

              systems.oauth2.step-ca = {
                displayName = "step-ca Certificate Authority";
                originUrl = "https://${hostConfig.hostSpec.domains.ca.domain}/oidc/callback";
                originLanding = "https://${hostConfig.hostSpec.domains.ca.domain}/";
                basicSecretFile = hostConfig.sops.secrets."step-ca/oidc-client-secret".path;
                preferShortUsername = true;

                scopeMaps.step_ca_users = [
                  "openid"
                  "email"
                  "profile"
                ];
              };

              systems.oauth2.step-ca-enroll = {
                displayName = "Get Client Certificate";
                originUrl = "https://${hostConfig.hostSpec.domains.ca.domain}/callback";
                originLanding = "https://${hostConfig.hostSpec.domains.ca.domain}/enroll";
                basicSecretFile = hostConfig.sops.secrets."step-ca-enroll/oidc-client-secret-raw".path;
                preferShortUsername = true;

                scopeMaps.step_ca_enroll_users = [
                  "openid"
                  "email"
                  "profile"
                ];
              };
            };
          };

          # Minimal container attempt
          environment.defaultPackages = lib.mkForce [ ];
          environment.systemPackages = lib.mkForce (
            [ pkgs.kanidm ] # Always include kanidm
            ++ lib.optionals enableShellAccess [
              pkgs.bash
              pkgs.coreutils
              pkgs.util-linux
            ]
          );

          # Disable all optional programs
          programs.command-not-found.enable = false;
          programs.nano.enable = lib.mkForce false;
          programs.vim.enable = lib.mkForce false;
          programs.bash.enableCompletion = false;
          programs.less.enable = lib.mkForce false;

          # Minimal system utilities (can't remove completely without breaking)
          environment.stub-ld.enable = false; # No stub ld for non-NixOS binaries

          # Disable documentation
          documentation.enable = false;
          documentation.man.enable = false;
          documentation.info.enable = false;
          documentation.doc.enable = false;

          # Limit journal size and retention
          # View logs from host: journalctl -M kanidm
          # Or: journalctl --directory=/var/lib/nixos-containers/kanidm/var/log/journal
          services.journald.extraConfig = ''
            SystemMaxUse=100M
            MaxRetentionSec=7day
          '';

          # Additional hardening for kanidm service (inside container)
          # Most hardening is already applied by the NixOS kanidm module
          systemd.services.kanidm.serviceConfig = {
            # The only meaningful addition: strict filesystem protection
            # Default: service has full access to OS file hierarchy (exposure: 0.2)
            # With strict: everything read-only except /var/lib/kanidm
            ProtectSystem = "strict";
            ReadWritePaths = [ "/var/lib/kanidm" ];
          };

          # Create necessary directories and fix certificate ownership
          systemd.tmpfiles.rules = [
            "d ${builtins.dirOf kanidmData} 0755 root root -"
            "d ${kanidmData} 0755 kanidm kanidm -"
            "d ${kanidmData}/.cache 0755 kanidm kanidm -"
            "d /etc/ssl/certs/kanidm 0755 root root -"
            "d /etc/ssl/certs/kanidm 0755 root root -"
          ];

          users.users.kanidm = {
            isSystemUser = true;
            group = "kanidm";
            extraGroups = [ "haproxy" ]; # Add to haproxy group for certificate access
            uid = 993;
            home = "/var/lib/kanidm";
            createHome = true;
          };
          users.groups.kanidm = {
            gid = 993;
          };
          # Create haproxy group with same GID as host for certificate access
          users.groups.haproxy = {
            gid = 996;
          };
        }
      ];
    };

  # Host systemd configuration for this container
  systemd = lib.mkMerge [
    (lib.custom.mkContainerSystemd "kanidm" { })
    {
      # Systemd hardening for kanidm container
      services."container@kanidm".serviceConfig = {
        ProtectSystem = "full";
        ProtectHome = true;
        PrivateTmp = true;

        # Privilege restrictions
        # NoNewPrivileges = true; # Disabled: breaks kanidm service (SECCOMP error)
        ProtectKernelTunables = true;
        # ProtectControlGroups = true; # Disabled: breaks container cgroup creation
        RestrictRealtime = true;
        # LockPersonality = true; # Disabled: Breaks systemd-logind in container
      };
    }
  ];

}
// (lib.custom.mkContainerDirs "kanidm" [
  "/mnt/storage/kanidm"
])
