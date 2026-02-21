# Jellyfin media server in a NixOS container, managed by jellarr
#
# Provides: custom.services.jellyfin options
# Produces: container definition, reverse proxy registration, tmpfiles, sops secrets
#
# Requires: networking.nix to be imported separately (handled by other container files in nas-base.nix)
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  cfg = config.custom.services.jellyfin;
  net = lib.custom.mkContainerNetworkConfig config cfg.network "jellyfin";
  hostConfig = config;

  jellyfinMedia = "/var/lib/jellyfin";
  jellarrModule = inputs.jellarr.nixosModules.default;

  uid = toString cfg.uid;
  gid = toString cfg.gid;

  extraGroups =
    cfg.extraGroups
    ++ lib.optionals cfg.gpu.enable [
      "video"
      "render"
    ];

  sopsFolder = builtins.toString inputs.nix-secrets + "/sops";
in
{
  options.custom.services.jellyfin = {
    enable = lib.mkEnableOption "Jellyfin media server container with jellarr management";

    uid = lib.mkOption {
      type = lib.types.int;
      default = 10100;
      description = "UID for jellyfin user on both host and container";
    };

    gid = lib.mkOption {
      type = lib.types.int;
      default = 10100;
      description = "GID for jellyfin group on both host and container";
    };

    extraGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "media" ];
      description = "Extra groups for the jellyfin user";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "jellyfin.${config.hostSpec.domain}";
      description = "FQDN for the Jellyfin reverse proxy virtual host";
    };

    network = lib.mkOption {
      type = lib.types.str;
      default = "arr";
      description = "Which containerNetwork to place jellyfin on";
    };

    hostOctet = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = "Host octet for the container IP in the network subnet. Will be replaced by auto-assignment later.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8096;
      description = "Jellyfin HTTP port";
    };

    applicationDataPath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/jellyfin";
      description = "Host path for application data";
    };

    backupPath = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/storage/jellyfin/backups";
      description = "Host path for Jellyfin backups";
    };

    gpu = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable GPU hardware acceleration for transcoding";
      };
      type = lib.mkOption {
        type = lib.types.enum [
          "qsv"
          "vaapi"
          "nvenc"
          "none"
        ];
        default = "qsv";
        description = "Hardware acceleration type";
      };
      renderDevice = lib.mkOption {
        type = lib.types.str;
        default = "/dev/dri/by-path/pci-0000:00:02.0-render";
        description = "Path to GPU render device";
      };
      cardDevice = lib.mkOption {
        type = lib.types.str;
        default = "/dev/dri/by-path/pci-0000:00:02.0-card";
        description = "Path to GPU card device";
      };
    };

    libraries = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Library display name";
            };
            collectionType = lib.mkOption {
              type = lib.types.enum [
                "movies"
                "tvshows"
                "music"
                "musicvideos"
                "homevideos"
                "boxsets"
                "books"
                "mixed"
              ];
              description = "Jellyfin collection type";
            };
            paths = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              description = "Media paths inside the container";
            };
          };
        }
      );
      default = [
        {
          name = "Movies";
          collectionType = "movies";
          paths = [ "/media/movies" ];
        }
        {
          name = "Series";
          collectionType = "tvshows";
          paths = [ "/media/tv" ];
        }
      ];
      description = "Media library definitions";
    };

    mediaMounts = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        "/media/movies" = "/mnt/storage/arr/media/movies";
        "/media/tv" = "/mnt/storage/arr/media/tv";
      };
      description = "Container path → host path mappings for media directories (read-only bind mounts)";
    };

    jellarr = { };
  };

  # Implementation
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.custom.mkContainerServiceConfig "jellyfin" { })
      {
        # Assert the extraGroups have been defined on host
        assertions = map (group: {
          assertion = config.users.groups ? ${group};
          message = "custom.services.jellyfin: extraGroups references group '${group}' which is not defined";
        }) cfg.extraGroups;

        # Create user on host
        users.users.jellyfin = {
          isSystemUser = true;
          group = "jellyfin";
          inherit extraGroups;
          uid = cfg.uid;
        };
        users.groups.jellyfin.gid = cfg.gid;

        # Register reverse proxy
        custom.reverseProxy.virtualHosts.jellyfin = {
          domain = cfg.domain;
          backendHost = net.containerIP;
          backendPort = cfg.port;
          backendSSL = false;
        };

        # Register container network
        hostSpec.networking.containerNetworks.${cfg.network} = {
          bridge = lib.mkDefault "${cfg.network}-bridge";
          subnet = lib.mkDefault "10.0.1.0/24";
          gateway = lib.mkDefault "10.0.1.1";
          containers.jellyfin = lib.mkDefault cfg.hostOctet;
        };

        # Setup bindmount directories
        systemd.tmpfiles.rules = [
          "d /var/lib/jellyfin 0755 ${uid} ${gid} -"
          "d ${cfg.backupPath} 0755 ${uid} ${gid} -"
        ] ++ (lib.mapAttrsToList (_: hostPath:
          "d ${hostPath} 0775 ${uid} ${toString config.users.groups.media.gid} -"
        ) cfg.mediaMounts);

        # Fetch secrets
        sops.secrets = {
          # openssl rand -base64 48
          "jellarr/api-key" = {
            sopsFile = "${sopsFolder}/shared.yaml";
            owner = "root";
            group = "root";
            mode = "0400";
          };
        }
        // lib.mapAttrs' (username: _: {
          name = "jellarr/passwords/${username}";
          value = {
            sopsFile = "${sopsFolder}/shared.yaml";
            owner = "root";
            group = "root";
            mode = "0400";
          };
        }) config.hostSpec.services.jellyfin.users;

        sops.templates."jellarr-env" = {
          content = ''
            JELLARR_API_KEY=${config.sops.placeholder."jellarr/api-key"}
          '';
          owner = "root";
          group = "root";
          mode = "0400";
        };

        # Container definition
        containers.jellyfin = {
          autoStart = true;
          ephemeral = true;

          bindMounts = lib.mkMerge [
            # Application data
            {
              "${jellyfinMedia}" = {
                hostPath = cfg.applicationDataPath;
                isReadOnly = false;
              };
            }

            # Backup path
            {
              "${jellyfinMedia}/backups" = {
                hostPath = cfg.backupPath;
                isReadOnly = false;
              };
            }

            # Media directories
            (lib.mapAttrs (containerPath: hostPath: {
              inherit hostPath;
              isReadOnly = true;
            }) cfg.mediaMounts)

            # Secrets
            {
              "/run/secrets" = {
                hostPath = "/run/secrets";
                isReadOnly = true;
              };
              "/run/jellarr-env" = {
                hostPath = config.sops.templates."jellarr-env".path;
                isReadOnly = true;
              };
            }

            # GPU device passthrough
            (lib.mkIf cfg.gpu.enable {
              "/dev/dri" = {
                hostPath = "/dev/dri";
                isReadOnly = false;
              };
            })
          ];

          # GPU device permissions
          allowedDevices = lib.mkIf cfg.gpu.enable [
            {
              node = cfg.gpu.renderDevice;
              modifier = "rwm";
            }
            {
              node = cfg.gpu.cardDevice;
              modifier = "rwm";
            }
          ];

          # Network
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
            (lib.custom.mkContainerBaseConfig (net // { inherit (config.hostSpec) stateVersion; }))
            {
              imports = [ jellarrModule ];

              # GPU drivers inside container
              # This may not be needed ?
              # See https://discourse.nixos.org/t/jellyfin-in-a-nixos-systemd-container-with-nvidia-hardware-acceleration/62678
              environment.sessionVariables = lib.mkIf cfg.gpu.enable {
                LIBVA_DRIVER_NAME = "iHD";
              };
              hardware.graphics = lib.mkIf cfg.gpu.enable {
                enable = true;
                extraPackages = hostConfig.hardware.graphics.extraPackages;
              };

              services.jellyfin = {
                enable = true;
                openFirewall = true;
                forceEncodingConfig = cfg.gpu.enable;
                hardwareAcceleration = lib.mkIf cfg.gpu.enable {
                  enable = true;
                  type = cfg.gpu.type;
                  device = cfg.gpu.renderDevice;
                };
                transcoding = lib.mkIf cfg.gpu.enable {
                  enableHardwareEncoding = true;
                  enableToneMapping = true;
                  enableIntelLowPowerEncoding = true;
                  hardwareDecodingCodecs = {
                    h264 = true;
                    hevc = true;
                    hevc10bit = true;
                    mpeg2 = true;
                    vc1 = true;
                    vp9 = true;
                    av1 = true;
                  };
                  hardwareEncodingCodecs = {
                    hevc = true;
                  };
                };
              };

              systemd.timers.jellarr.enable = false;
              # Run once after Jellyfin is ready after rebuild
              systemd.services.jellarr = {
                after = [ "jellyfin.service" ];
                wants = [ "jellyfin.service" ];
                wantedBy = [ "multi-user.target" ];
                serviceConfig = {
                  Restart = "on-failure";
                  RestartSec = "5s";
                };
              };

              # Jellarr configures jellyfin via API during runtime
              services.jellarr = {
                enable = true;
                user = "jellyfin";
                group = "jellyfin";
                environmentFile = "/run/jellarr-env";

                bootstrap = {
                  enable = true;
                  apiKeyFile = "/run/secrets/jellarr/api-key";
                };

                config = {
                  version = 1;
                  base_url = "http://localhost:${toString cfg.port}";

                  library = {
                    virtualFolders = map (lib_: {
                      name = lib_.name;
                      collectionType = lib_.collectionType;
                      libraryOptions = {
                        pathInfos = map (p: { path = p; }) lib_.paths;
                      };
                    }) cfg.libraries;
                  };

                  users = lib.mapAttrsToList (username: userConfig: {
                    name = username;
                    passwordFile = hostConfig.sops.secrets."jellarr/passwords/${username}".path;
                    policy = {
                      isAdministrator = userConfig.isAdmin;
                    };
                  }) hostConfig.hostSpec.services.jellyfin.users;

                  system = {
                    trickplayOptions = lib.mkIf cfg.gpu.enable {
                      enableHwAcceleration = true;
                      enableHwEncoding = true;
                    };
                  };

                  startup = {
                    completeStartupWizard = true;
                  };
                };
              };

              # Container user/group
              users.users.jellyfin = {
                uid = cfg.uid;
                inherit extraGroups;
              };
              # Mirror extra groups from host with matching GIDs
              users.groups = { jellyfin.gid = cfg.gid; } // lib.genAttrs cfg.extraGroups (group: {
                gid = hostConfig.users.groups.${group}.gid;
              });
            }
          ];
        };
      }
    ]
  );
}
