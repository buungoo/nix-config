{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  cfg = config.custom.services.immich;
  net = lib.custom.mkContainerNetworkConfig config cfg.network "immich";
  hostConfig = config;

  immichMedia = "/var/lib/immich";
  uid = toString cfg.uid;
  gid = toString cfg.gid;

  sopsFolder = builtins.toString inputs.nix-secrets + "/sops";
in
{
  options.custom.services.immich = {
    enable = lib.mkEnableOption "Immich photo management solution";

    uid = lib.mkOption {
      type = lib.types.int;
      default = 10900;
      description = "UID for immich user on both host and container";
    };

    gid = lib.mkOption {
      type = lib.types.int;
      default = 10900;
      description = "GID for immich group on both host and container";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "immich.${config.hostSpec.domain}";
      description = "FQDN for the Immich reverse proxy virtual host";
    };

    network = lib.mkOption {
      type = lib.types.str;
      default = "immich";
      description = "Which containerNetwork to place immich on";
    };

    hostOctet = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = "Host octet for the container IP";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 2283;
      description = "Immich HTTP port";
    };

    applicationDataPath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/immich";
      description = "Host path for application data (database, etc.)";
    };

    mediaLocation = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/storage/immich";
      description = "Host path for Immich media storage (library, thumbs, etc.)";
    };

    gpu = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable GPU hardware acceleration";
      };
      renderDevice = lib.mkOption {
        type = lib.types.str;
        default = hostConfig.hostSpec.gpu.renderDevice;
        description = "Path to GPU render device";
      };
      cardDevice = lib.mkOption {
        type = lib.types.str;
        default = hostConfig.hostSpec.gpu.cardDevice;
        description = "Path to GPU card device";
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.custom.mkContainerServiceConfig "immich" { })
      {
        # Create user on host
        users.users.immich = {
          isSystemUser = true;
          group = "immich";
          extraGroups = lib.optionals cfg.gpu.enable [
            "video"
            "render"
          ];
          uid = cfg.uid;
        };
        users.groups.immich.gid = cfg.gid;

        # Register reverse proxy
        custom.reverseProxy.virtualHosts.immich = {
          domain = cfg.domain;
          backendHost = net.containerIP;
          backendPort = cfg.port;
          backendSSL = false;
        };

        # Register container network
        hostSpec.networking.containerNetworks.${cfg.network} = {
          bridge = lib.mkDefault "${cfg.network}-bridge";
          subnet = lib.mkDefault "10.0.0.0/24";
          gateway = lib.mkDefault "10.0.0.1";
          containers.immich = lib.mkDefault cfg.hostOctet;
        };

        # Sops secrets
        sops.secrets."immich/oidc-client-secret" = {
          sopsFile = "${sopsFolder}/shared.yaml";
          owner = "root";
          group = "kanidm";
          mode = "0440";
        };

        # Kanidm OAuth client
        custom.kanidm.oauthClients.immich = {
          displayName = "Immich";
          originUrl = [
            "https://${cfg.domain}/auth/login"
            "https://${cfg.domain}/api/oauth/mobile-redirect"
            "https://${cfg.domain}/user-settings"
            "app.immich:///oauth-callback"
            "app.immich://oauth-callback"
            "app.immich:/oauth-callback"
            "com.alextran.immich://oauth-callback"
          ];
          originLanding = "https://${cfg.domain}/";
          secretFile = config.sops.secrets."immich/oidc-client-secret".path;
          enableLegacyCrypto = true;
          scopeMap.immich_users = [
            "openid"
            "email"
            "profile"
          ];
        };

        # Setup bindmount directories
        systemd.tmpfiles.rules = [
          "d ${cfg.applicationDataPath} 0700 ${uid} ${gid} -"
          "d ${cfg.mediaLocation} 0700 ${uid} ${gid} -"
          "d ${cfg.mediaLocation}/encoded-video 0700 ${uid} ${gid} -"
          "d ${cfg.mediaLocation}/thumbs 0700 ${uid} ${gid} -"
          "d ${cfg.mediaLocation}/upload 0700 ${uid} ${gid} -"
          "d ${cfg.mediaLocation}/library 0700 ${uid} ${gid} -"
          "d ${cfg.mediaLocation}/profile 0700 ${uid} ${gid} -"
          "d ${cfg.mediaLocation}/backups 0700 ${uid} ${gid} -"
          "d /var/cache/immich 0700 ${uid} ${gid} -"

          # Recursively fix ownership for the new UID/GID during migration
          "Z ${cfg.applicationDataPath} 0700 ${uid} ${gid} -"
          "Z ${cfg.mediaLocation} 0700 ${uid} ${gid} -"
          "Z /var/cache/immich 0700 ${uid} ${gid} -"
        ];
        # Alternative structured settings for comparison:
        # systemd.tmpfiles.settings."10-immich" = {
        #   "${cfg.applicationDataPath}" = {
        #     d = { mode = "0700"; user = uid; group = gid; };
        #     Z = { mode = "0700"; user = uid; group = gid; };
        #   };
        #   "${cfg.mediaLocation}" = {
        #     d = { mode = "0700"; user = uid; group = gid; };
        #     Z = { mode = "0700"; user = uid; group = gid; };
        #   };
        #   "${cfg.mediaLocation}/encoded-video".d = { mode = "0700"; user = uid; group = gid; };
        #   "${cfg.mediaLocation}/thumbs".d = { mode = "0700"; user = uid; group = gid; };
        #   "${cfg.mediaLocation}/upload".d = { mode = "0700"; user = uid; group = gid; };
        #   "${cfg.mediaLocation}/library".d = { mode = "0700"; user = uid; group = gid; };
        #   "${cfg.mediaLocation}/profile".d = { mode = "0700"; user = uid; group = gid; };
        #   "${cfg.mediaLocation}/backups".d = { mode = "0700"; user = uid; group = gid; };
        # };

        # Container definition
        containers.immich = {
          autoStart = true;
          ephemeral = true;

          bindMounts = lib.mkMerge [
            {
              "${immichMedia}" = {
                hostPath = cfg.mediaLocation;
                isReadOnly = false;
              };
              "/var/lib/postgresql" = {
                hostPath = cfg.applicationDataPath;
                isReadOnly = false;
              };
              "/var/cache/immich" = {
                hostPath = "/var/cache/immich";
                isReadOnly = false;
              };
              "/dev/bus/usb" = {
                hostPath = "/dev/bus/usb";
                isReadOnly = true;
              };
              "/run/secrets" = {
                hostPath = "/run/secrets";
                isReadOnly = true;
              };
            }
            (lib.mkIf cfg.gpu.enable {
              "/dev/dri" = {
                hostPath = "/dev/dri";
                isReadOnly = false;
              };
            })
          ];

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
              environment.systemPackages = [ pkgs.clinfo ];
              environment.sessionVariables = lib.mkIf cfg.gpu.enable {
                LIBVA_DRIVER_NAME = "iHD";
              };

              hardware.graphics = lib.mkIf cfg.gpu.enable {
                enable = true;
                extraPackages = hostConfig.hardware.graphics.extraPackages ++ [
                  pkgs.intel-compute-runtime
                  pkgs.intel-media-driver
                  pkgs.intel-ocl
                  pkgs.level-zero
                ];
              };

              services.immich = {
                enable = true;
                package = pkgs.immich;
                database.enable = true;
                host = net.containerIP;
                openFirewall = true;
                mediaLocation = immichMedia;
                accelerationDevices = lib.optionals cfg.gpu.enable [
                  cfg.gpu.renderDevice
                  cfg.gpu.cardDevice
                ];
                environment = {
                  TZ = "Europe/Stockholm";
                  # Fix matplotlib and other python tools
                  MPLCONFIGDIR = "/tmp/matplotlib";
                };
                machine-learning.enable = true;
                machine-learning.environment = {
                  MACHINE_LEARNING_WORKERS = "1";
                  MACHINE_LEARNING_MAX_BATCH_SIZE__FACIAL_RECOGNITION = "1";
                  MACHINE_LEARNING_OPENVINO_PRECISION = "FP16";
                  MACHINE_LEARNING_WORKER_TIMEOUT = lib.mkForce "300";
                  MACHINE_LEARNING_CACHE_FOLDER = "/var/cache/immich";
                  # AUTO mode is the most robust for Intel iGPUs
                  OPENVINO_DEVICE = "AUTO";
                  OPENVINO_PERFORMANCE_HINT = "LATENCY";
                };
                settings = {
                  backup.database.enabled = false;
                  ffmpeg = {
                    accel = "qsv";
                    accelDecode = true;
                  };
                  machineLearning = {
                    clip = {
                      modelName = "ViT-L-14-336__openai";
                    };
                    facialRecognition = {
                      modelName = "buffalo_l";
                    };
                  };
                  oauth = {
                    enabled = true;
                    autoLaunch = true;
                    autoRegister = true;
                    buttonText = "Login";
                    clientId = "immich";
                    clientSecret._secret = hostConfig.sops.secrets."immich/oidc-client-secret".path;
                    issuerUrl = "https://${hostConfig.custom.reverseProxy.virtualHosts.auth.domain}/oauth2/openid/immich";
                    scope = "openid profile email";
                    signingAlgorithm = "RS256";
                    mobileRedirectUri = "app.immich:///oauth-callback";
                  };
                  passwordLogin.enabled = false;
                  server.externalDomain = "https://${cfg.domain}";
                };
              };

              systemd.services.immich-init-markers = {
                description = "Create Immich marker files for mount verification";
                wantedBy = [ "immich-server.service" ];
                before = [ "immich-server.service" ];
                serviceConfig = {
                  Type = "oneshot";
                  RemainAfterExit = true;
                  User = "immich";
                  Group = "immich";
                };
                script = ''
                  for dir in encoded-video thumbs upload library profile backups; do
                    marker="${immichMedia}/$dir/.immich"
                    if [[ ! -f "$marker" ]]; then
                      touch "$marker"
                    fi
                  done
                '';
              };

              users.users.immich = {
                isSystemUser = true;
                inherit (cfg) uid;
                group = "immich";
                home = "/var/lib/immich";
                extraGroups = lib.optionals cfg.gpu.enable [
                  "video"
                  "render"
                ];
              };
              users.groups.immich.gid = cfg.gid;
            }
          ];
        };
      }
    ]
  );
}
