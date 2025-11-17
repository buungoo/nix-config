# step-ca Certificate Authority Container
# Private CA for issuing internal TLS certificates and client mTLS certificates
# Integrated with Kanidm OIDC for user authentication
#
# Access step-ca at https://ca.<domain>.<TLD>
# CLI: step-cli for certificate management
#
# P12 Password Configuration:
# The password for .p12 files is stored in SOPS secrets at:
# step-ca-enroll/p12-password (format: P12_PASSWORD=<value>)
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
{
  imports = [
    (./networking.nix)
  ];

  # Create step-ca user and group on host to match container UID/GID
  # The NixOS step-ca service auto-assigns UID/GID, so we match it on the host
  # This ensures bind-mounted directories have correct ownership across host/container boundary
  users.users.step-ca = {
    isSystemUser = true;
    group = "step-ca";
    extraGroups = [ "ca-proxy" ];
    uid = 998;
  };
  users.groups.step-ca = {
    gid = 998;
  };

  # Shared group for CA certificate access by reverse-proxy
  users.groups.ca-proxy = {
    gid = 986;
  };

  hostSpec.domains.ca = {
    domain = "ca.${config.hostSpec.domain}";
    public = false;
    backendHost = "10.0.9.2";
    backendPort = 3000; # step-ca enrollment service
    backendSSL = false;
  };

  hostSpec.networking.containerNetworks.ca.bridge = lib.mkDefault "ca-bridge";
  hostSpec.networking.containerNetworks.ca.subnet = lib.mkDefault "10.0.9.0/24";
  hostSpec.networking.containerNetworks.ca.gateway = lib.mkDefault "10.0.9.1";
  hostSpec.networking.containerNetworks.ca.containers.step-ca = lib.mkDefault 2;

  containers.step-ca =
    let
      net = lib.custom.mkContainerNetworkConfig config "ca" "step-ca";
      hostConfig = config;
    in
    {
      autoStart = true;

      bindMounts = {
        # step-ca data directory (contains CA keys, certificates, config)
        "/var/lib/step-ca" = {
          hostPath = "/mnt/storage/step-ca";
          isReadOnly = false;
        };
        # step-ca database stays on root
        # (no bind mount = /var/lib/nixos-containers/step-ca/var/lib/step-ca-db on host)
        # Mount ACME certificates for step-ca web UI HTTPS
        "/etc/ssl/certs/step-ca" = {
          hostPath = hostConfig.security.acme.certs."ca.${hostConfig.hostSpec.domain}".directory;
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
          hostPort = 9443; # step-ca HTTPS API
          containerPort = 9443;
        }
        {
          hostPort = 3000; # enrollment service HTTP
          containerPort = 3000;
        }
      ];

      config = lib.mkMerge [
        (lib.custom.mkContainerBaseConfig net)
        {
          environment.systemPackages = with pkgs; [
            step-ca
            step-cli
            step-ca-enroll
          ];

          services.step-ca = {
            enable = true;
            address = "0.0.0.0";
            port = 9443;
            openFirewall = true;

            intermediatePasswordFile = hostConfig.sops.secrets."step-ca/intermediate-password".path;

            # Main step-ca configuration
            # Paths match where step ca init creates files: /var/lib/step-ca/.step/
            settings = {
              # Root and intermediate CA certificates
              root = "/var/lib/step-ca/.step/certs/root_ca.crt";
              crt = "/var/lib/step-ca/.step/certs/intermediate_ca.crt";
              key = "/var/lib/step-ca/.step/secrets/intermediate_ca_key";

              # DNS names that step-ca will accept requests for
              dnsNames = [ "ca.${hostConfig.hostSpec.domain}" ];

              # Enable debug logging
              logger = {
                format = "text";
              };

              # Database for certificate tracking and revocation
              # Using bbolt instead of badgerv2 to avoid mmap issues on btrfs with COW
              db = {
                type = "bbolt";
                dataSource = "/var/lib/step-ca-db/step-ca.db";
              };

              # TLS configuration for step-ca API
              tls = {
                cipherSuites = [
                  "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256"
                  "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256"
                ];
                minVersion = 1.2;
                maxVersion = 1.3;
              };

              # Authority configuration
              authority = {
                provisioners = [
                  # ACME provisioner for automatic certificate issuance
                  {
                    type = "ACME";
                    name = "acme";
                    forceCN = true;
                    claims = {
                      minTLSCertDuration = "5m";
                      maxTLSCertDuration = "2160h"; # 90 days
                      defaultTLSCertDuration = "2160h";
                    };
                  }

                  # OIDC provisioner for user authentication via Kanidm (step-ca client)
                  {
                    type = "OIDC";
                    name = "kanidm";
                    configurationEndpoint = "https://auth.${hostConfig.hostSpec.domain}/oauth2/openid/step-ca/.well-known/openid-configuration";
                    clientID = "step-ca";
                    clientSecret = "$OIDC_CLIENT_SECRET"; # Will be replaced from SOPS
                    admins = [ hostConfig.hostSpec.users.bungo.userEmail ];
                    domains = [ hostConfig.hostSpec.domain ];
                    claims = {
                      minTLSCertDuration = "5m";
                      maxTLSCertDuration = "19800h"; # 825 days (iOS max for client certs)
                      defaultTLSCertDuration = "19800h";
                      enableSSHCA = true;
                      minUserSSHCertDuration = "5m";
                      maxUserSSHCertDuration = "24h";
                      defaultUserSSHCertDuration = "16h";
                    };
                  }

                  # OIDC provisioner for enrollment service (step-ca-enroll client)
                  {
                    type = "OIDC";
                    name = "kanidm-enroll";
                    configurationEndpoint = "https://auth.${hostConfig.hostSpec.domain}/oauth2/openid/step-ca-enroll/.well-known/openid-configuration";
                    clientID = "step-ca-enroll";
                    clientSecret = "$OIDC_CLIENT_SECRET_ENROLL"; # Will be replaced from SOPS
                    # No domain restriction - allow any authenticated user
                    claims = {
                      minTLSCertDuration = "5m";
                      maxTLSCertDuration = "19800h"; # 825 days (iOS max for client certs)
                      defaultTLSCertDuration = "19800h";
                    };
                  }
                ];
              };
            };
          };

          # Override step-ca service configuration
          systemd.services.step-ca = {
            serviceConfig = {
              DynamicUser = lib.mkForce false;
              User = "step-ca";
              Group = "step-ca";

              # Override ExecStart to use our writable config file
              ExecStart = lib.mkForce [
                "" # Clear the default ExecStart
                "${pkgs.step-ca}/bin/step-ca /var/lib/step-ca/config/ca.json --password-file \${CREDENTIALS_DIRECTORY}/intermediate_password"
              ];
            };
            preStart = ''
              # Copy the Nix-generated config to a writable location
              mkdir -p /var/lib/step-ca/config
              cp -f /etc/static/smallstep/ca.json /var/lib/step-ca/config/ca.json
              chmod 640 /var/lib/step-ca/config/ca.json
              chown step-ca:step-ca /var/lib/step-ca/config/ca.json

              # Load secrets from bind-mounted host secrets and replace placeholders
              # The secrets are mounted at /run/secrets from the host
              OIDC_SECRET_STEPCA=$(cat /run/secrets/step-ca/oidc-client-secret | cut -d= -f2-)
              OIDC_SECRET_ENROLL=$(cat /run/secrets/step-ca-enroll/oidc-client-secret-raw)

              # Replace longer placeholder first to avoid partial replacement
              ${pkgs.gnused}/bin/sed -i \
                -e "s|\$OIDC_CLIENT_SECRET_ENROLL|$OIDC_SECRET_ENROLL|g" \
                -e "s|\$OIDC_CLIENT_SECRET|$OIDC_SECRET_STEPCA|g" \
                /var/lib/step-ca/config/ca.json
            '';
          };

          # Enrollment service for OIDC-based client certificate enrollment
          systemd.services.step-ca-enroll = {
            description = "step-ca OIDC enrollment service for client certificates";
            after = [
              "network-online.target"
              "step-ca.service"
            ];
            wants = [ "network-online.target" ];
            wantedBy = [ "multi-user.target" ];

            environment = {
              KANIDM_URL = "https://auth.${hostConfig.hostSpec.domain}";
              OIDC_CLIENT_ID = "step-ca-enroll";
              REDIRECT_URL = "https://ca.${hostConfig.hostSpec.domain}/callback";
              STEP_CA_URL = "https://127.0.0.1:9443";
              BIND_ADDR = "0.0.0.0:3000";
            };

            serviceConfig = {
              Type = "simple";
              Restart = "on-failure";
              RestartSec = "10s";
              User = "step-ca-enroll";
              Group = "step-ca-enroll";

              # Security hardening
              PrivateTmp = true;
              ProtectSystem = "strict";
              ProtectHome = true;
              NoNewPrivileges = true;
              PrivateDevices = true;
              ProtectKernelTunables = true;
              ProtectKernelModules = true;
              ProtectControlGroups = true;
              RestrictAddressFamilies = [
                "AF_INET"
                "AF_INET6"
              ];
              RestrictNamespaces = true;
              LockPersonality = true;
              RestrictRealtime = true;
              RestrictSUIDSGID = true;

              # Load secrets from sops (OIDC client secret and P12 password)
              EnvironmentFile = [
                hostConfig.sops.secrets."step-ca-enroll/oidc-client-secret".path
                hostConfig.sops.secrets."step-ca-enroll/p12-password".path
              ];
            };

            script = ''
              exec ${pkgs.step-ca-enroll}/bin/step-ca-enroll
            '';
          };

          # SystemD service to initialize step-ca on first boot
          # This creates the CA hierarchy if it doesn't exist
          systemd.services.step-ca-init = {
            description = "Initialize step-ca Certificate Authority";
            before = [ "step-ca.service" ];
            wantedBy = [ "multi-user.target" ];
            # Only run if CA doesn't exist yet
            unitConfig.ConditionPathExists = "!/var/lib/step-ca/config/ca.json";

            serviceConfig = {
              Type = "oneshot";
              User = "step-ca";
              Group = "step-ca";
              # Read password from SOPS secret
              EnvironmentFile = hostConfig.sops.secrets."step-ca/intermediate-password".path;
            };

            # Set STEPPATH to control where step CLI creates files
            # Use .step subdirectory to match where step-ca service expects files
            environment.STEPPATH = "/var/lib/step-ca/.step";

            script = ''
              # Initialize step-ca with ECDSA keys:
              # - Domain: ca.bungos.xyz
              # - Provisioner: Initial JWK provisioner
              # - Intermediate password from SOPS secret
              ${pkgs.step-cli}/bin/step ca init \
                --name="Bungos Internal CA" \
                --dns="ca.${hostConfig.hostSpec.domain}" \
                --address=":9443" \
                --provisioner="admin" \
                --password-file=${hostConfig.sops.secrets."step-ca/intermediate-password".path} \
                --deployment-type="standalone"

              # The init command creates:
              # - Root CA certificate (self-signed, ECDSA, 10 year validity)
              # - Intermediate CA certificate (signed by root, ECDSA, 5 year validity)
              # - Intermediate CA private key (encrypted with password)
              # - Initial JWK provisioner for admin access
              # - Default ca.json configuration

              echo "step-ca initialized successfully"
              echo "Root CA fingerprint:"
              ${pkgs.step-cli}/bin/step certificate fingerprint /var/lib/step-ca/.step/certs/root_ca.crt
            '';
          };

          # Helper script to get client certificates via OIDC
          # Users can run this to authenticate via Kanidm and get a client cert
          environment.etc."step-ca/get-client-cert.sh" = {
            text = ''
              #!/bin/sh
              # Get a client certificate via Kanidm OIDC authentication
              # Usage: get-client-cert.sh [output-dir]

              OUTPUT_DIR="''${1:-$HOME/.step}"
              mkdir -p "$OUTPUT_DIR"

              echo "Authenticating via Kanidm OIDC..."
              echo "This will open a browser window for login."

              ${pkgs.step-cli}/bin/step ca certificate \
                "$USER@${hostConfig.hostSpec.domain}" \
                "$OUTPUT_DIR/client.crt" \
                "$OUTPUT_DIR/client.key" \
                --provisioner="kanidm" \
                --provisioner-password-file=<(echo "") \
                --not-after=720h

              echo ""
              echo "Client certificate saved to: $OUTPUT_DIR/client.crt"
              echo "Client key saved to: $OUTPUT_DIR/client.key"
              echo ""
              echo "To use with curl:"
              echo "  curl --cert $OUTPUT_DIR/client.crt --key $OUTPUT_DIR/client.key https://immich.${hostConfig.hostSpec.domain}"
            '';
            mode = "0755";
          };

          # Open firewall
          networking.firewall.allowedTCPPorts = [
            9443
            3000
          ];

          # Create step-ca user and group
          users.users.step-ca = {
            isSystemUser = true;
            group = "step-ca";
            home = "/var/lib/step-ca";
            createHome = true;
          };
          users.groups.step-ca = { };

          # Create enrollment service user and group
          users.users.step-ca-enroll = {
            isSystemUser = true;
            group = "step-ca-enroll";
          };
          users.groups.step-ca-enroll = { };

          # Create necessary directories
          systemd.tmpfiles.rules = [
            "d /var/lib/step-ca 0755 step-ca step-ca -"
            "d /var/lib/step-ca/certs 0755 step-ca step-ca -"
            "d /var/lib/step-ca/secrets 0755 step-ca step-ca -"
            "d /var/lib/step-ca/db 0755 step-ca step-ca -"
            "d /var/lib/step-ca/config 0755 step-ca step-ca -"
            "d /var/lib/step-ca/templates 0755 step-ca step-ca -"
          ];
        }
      ];
    };

  # Host systemd configuration
  systemd = lib.mkMerge [
    (lib.custom.mkContainerSystemd "step-ca" { })
    {
      # Also ensure certificate files are group-readable after step-ca creates them
      services.step-ca-fix-cert-permissions = {
        description = "Fix step-ca certificate permissions for nginx mTLS";
        after = [ "container@step-ca.service" ];
        wantedBy = [
          "nginx.service"
          "haproxy.service"
        ];
        before = [
          "nginx.service"
          "haproxy.service"
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script =
          let
            caProxyGid = toString config.users.groups.ca-proxy.gid;
          in
          ''
            # Wait for certificates to exist
            for i in {1..30}; do
              if [[ -f /mnt/storage/step-ca/.step/certs/root_ca.crt ]]; then
                break
              fi
              sleep 1
            done

            # Set group-readable permissions on certificate files
            if [[ -f /mnt/storage/step-ca/.step/certs/root_ca.crt ]]; then
              chmod 640 /mnt/storage/step-ca/.step/certs/root_ca.crt
              chmod 640 /mnt/storage/step-ca/.step/certs/intermediate_ca.crt
              chgrp ${caProxyGid} /mnt/storage/step-ca/.step/certs/root_ca.crt
              chgrp ${caProxyGid} /mnt/storage/step-ca/.step/certs/intermediate_ca.crt

              # Create CA bundle with root + intermediate for nginx verification
              cat /mnt/storage/step-ca/.step/certs/intermediate_ca.crt \
                  /mnt/storage/step-ca/.step/certs/root_ca.crt \
                  > /mnt/storage/step-ca/.step/certs/ca_bundle.crt
              chmod 640 /mnt/storage/step-ca/.step/certs/ca_bundle.crt
              chgrp ${caProxyGid} /mnt/storage/step-ca/.step/certs/ca_bundle.crt
            fi
          '';
      };
    }
  ];

}
// (
  let
    # Use host step-ca user UID/GID for directory ownership
    stepCaUid = toString config.users.users.step-ca.uid;
    stepCaGid = toString config.users.groups.step-ca.gid;
    caProxyGid = toString config.users.groups.ca-proxy.gid;
  in
  lib.custom.mkContainerDirs "step-ca" [
    # step-ca config and certificates on mergerfs
    {
      path = "/mnt/storage/step-ca";
      owner = stepCaUid;
      group = stepCaGid;
      mode = "0755";
    }
    # Database stays in container's own filesystem, no host directory needed
  ]
)
