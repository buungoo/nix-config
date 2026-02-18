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

  extraGroups = [ "media" ] ++ lib.optionals cfg.gpu.enable [ "video" "render" ];

  sopsFolder = builtins.toString inputs.nix-secrets + "/sops";
in
{
  # ======================== OPTIONS ========================
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

    mediaGid = lib.mkOption {
      type = lib.types.int;
      default = 5000;
      description = "GID for shared media group (used across media containers)";
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

    backupPath = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/storage/jellyfin/backups";
      description = "Host path for Jellyfin backups (snapraid-protected)";
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
          name = "TV Shows";
          collectionType = "tvshows";
          paths = [ "/media/tvshows" ];
        }
      ];
      description = "Media library definitions";
    };

    mediaMounts = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        "/media/movies" = "/mnt/storage/arr/media/movies";
        "/media/tvshows" = "/mnt/storage/arr/media/tvshows";
      };
      description = "Container path → host path mappings for media directories (read-only bind mounts)";
    };

    jellarr = { };
  };

  # ======================== IMPLEMENTATION ========================
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (lib.custom.mkContainerServiceConfig "jellyfin" { })
    {
    # --- Host user/group (matches container for bind mount ownership) ---
    users.users.jellyfin = {
      isSystemUser = true;
      group = "jellyfin";
      inherit extraGroups;
      uid = cfg.uid;
    };
    users.groups.jellyfin.gid = cfg.gid;
    users.groups.media.gid = cfg.mediaGid;

    # --- Reverse proxy registration ---
    custom.reverseProxy.virtualHosts.jellyfin = {
      domain = cfg.domain;
      backendHost = net.containerIP;
      backendPort = cfg.port;
      backendSSL = false;
    };

    # --- Container network registration ---
    hostSpec.networking.containerNetworks.${cfg.network} = {
      bridge = lib.mkDefault "${cfg.network}-bridge";
      subnet = lib.mkDefault "10.0.1.0/24";
      gateway = lib.mkDefault "10.0.1.1";
      containers.jellyfin = lib.mkDefault cfg.hostOctet;
    };

    # --- tmpfiles.rules (replaces mkContainerDirs) ---
    systemd.tmpfiles.rules = [
      "d /var/lib/jellyfin 0755 ${uid} ${gid} -"
      "d ${cfg.backupPath} 0755 ${uid} ${gid} -"
    ];

    # --- Sops secrets ---
    sops.secrets = {
      "jellarr/api-key" = {
        sopsFile = "${sopsFolder}/shared.yaml";
        owner = "root";
        group = "root";
        mode = "0400";
      };
    } // lib.mapAttrs' (username: _: {
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

    # --- Container definition ---
    containers.jellyfin = {
      autoStart = true;
      ephemeral = false;

      bindMounts = lib.mkMerge [
        # Application data
        {
          "${jellyfinMedia}" = {
            hostPath = "/var/lib/jellyfin";
            isReadOnly = false;
          };
        }

        # Backups on snapraid storage (nested inside app data mount)
        {
          "${jellyfinMedia}/backups" = {
            hostPath = cfg.backupPath;
            isReadOnly = false;
          };
        }

        # Media directories (read-only)
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
          node = config.hostSpec.gpu.renderDevice;
          modifier = "rwm";
        }
        {
          node = config.hostSpec.gpu.cardDevice;
          modifier = "rwm";
        }
      ];

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
        (lib.custom.mkContainerBaseConfig net)
        {
          imports = [ jellarrModule ];

          # --- GPU drivers inside container ---
          environment.sessionVariables = lib.mkIf cfg.gpu.enable {
            LIBVA_DRIVER_NAME = "iHD";
          };
          hardware.graphics = lib.mkIf cfg.gpu.enable {
            enable = true;
            extraPackages = hostConfig.hardware.graphics.extraPackages;
          };

          # --- Stock Jellyfin service ---
          services.jellyfin = {
            enable = true;
            openFirewall = true;
          };

          # --- Jellarr configuration management ---
          # Disable the timer — config only changes on rebuild, not at runtime
          systemd.timers.jellarr.enable = false;
          # Run once after Jellyfin is ready
          systemd.services.jellarr = {
            after = [ "jellyfin.service" ];
            wants = [ "jellyfin.service" ];
            wantedBy = [ "multi-user.target" ];
          };

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

              encoding = lib.mkIf cfg.gpu.enable {
                enableHardwareEncoding = true;
                hardwareAccelerationType = cfg.gpu.type;
                qsvDevice = lib.mkIf (cfg.gpu.type == "qsv") hostConfig.hostSpec.gpu.renderDevice;
                vaapiDevice = lib.mkIf (cfg.gpu.type == "vaapi") hostConfig.hostSpec.gpu.renderDevice;
                enableDecodingColorDepth10Hevc = true;
                allowHevcEncoding = true;
                allowAv1Encoding = false;
                hardwareDecodingCodecs = [
                  "h264"
                  "hevc"
                  "mpeg2video"
                  "vc1"
                  "vp9"
                  "av1"
                ];
              };

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

          # --- Container user/group (matches host) ---
          users.users.jellyfin = {
            uid = cfg.uid;
            inherit extraGroups;
          };
          users.groups.jellyfin.gid = cfg.gid;
          users.groups.media.gid = cfg.mediaGid;
        }
      ];
    };
  }
  ]);
}
