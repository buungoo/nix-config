# To test hardware acceleration (as jellyfin user):
# ffmpeg -hide_banner \
#  -init_hw_device qsv=hw:/dev/dri/renderD128 \
#  -f lavfi -i testsrc=size=128x128:rate=1 -t 1 \
#  -c:v h264_qsv -f null -
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

  users.users.jellyfin = {
    isSystemUser = true;
    group = "jellyfin";
    extraGroups = [ "media" ];
    uid = 994;
  };
  users.groups.jellyfin = {
    gid = 994;
  };
  users.groups.media = {
    gid = 5000;
  };

  hostSpec.domains.jellyfin = {
    domain = "jellyfin.${config.hostSpec.domain}";
    public = true;
    backendHost = "10.0.1.2";
    backendPort = 8096;
    backendSSL = false;
  };

  hostSpec.networking.containerNetworks.arr.bridge = lib.mkDefault "arr-bridge";
  hostSpec.networking.containerNetworks.arr.subnet = lib.mkDefault "10.0.1.0/24";
  hostSpec.networking.containerNetworks.arr.gateway = lib.mkDefault "10.0.1.1";
  hostSpec.networking.containerNetworks.arr.containers.jellyfin = lib.mkDefault 2;

  containers.jellyfin =
    let
      net = lib.custom.mkContainerNetworkConfig config "arr" "jellyfin";
      jellyfinMedia = "/var/lib/jellyfin";
      hostConfig = config;
      declarativeJellyfinModule = inputs.declarative-jellyfin.nixosModules.default;
    in
    {
      autoStart = true;

      bindMounts = {
        # Jellyfin directories on storage
        # Database stays on root
        "${jellyfinMedia}/config" = {
          hostPath = "/mnt/storage/jellyfin/config";
          isReadOnly = false;
        };
        "${jellyfinMedia}/log" = {
          hostPath = "/mnt/storage/jellyfin/log";
          isReadOnly = false;
        };
        "${jellyfinMedia}/metadata" = {
          hostPath = "/mnt/storage/jellyfin/metadata";
          isReadOnly = false;
        };
        "${jellyfinMedia}/playlists" = {
          hostPath = "/mnt/storage/jellyfin/playlists";
          isReadOnly = false;
        };
        "${jellyfinMedia}/plugins" = {
          hostPath = "/mnt/storage/jellyfin/plugins";
          isReadOnly = false;
        };
        "${jellyfinMedia}/root" = {
          hostPath = "/mnt/storage/jellyfin/root";
          isReadOnly = false;
        };
        "${jellyfinMedia}/backups" = {
          hostPath = "/mnt/storage/jellyfin/backups";
          isReadOnly = false;
        };
        "${jellyfinMedia}/wwwroot" = {
          hostPath = "/mnt/storage/jellyfin/wwwroot";
          isReadOnly = false;
        };
        # Note: "Subtitle Edit" omitted, systemd-nspawn doesn't support spaces in bind mount paths :(
        # Cache directory (separate from /var/lib/jellyfin)
        "/var/cache/jellyfin" = {
          hostPath = "/mnt/storage/jellyfin/cache";
          isReadOnly = false;
        };
        # Media directories
        "/media/movies" = {
          hostPath = "/mnt/storage/media/movies";
          isReadOnly = true;
        };
        "/media/tvshows" = {
          hostPath = "/mnt/storage/media/tvshows";
          isReadOnly = true;
        };
        # Pass the render device to the container
        "/dev/dri" = {
          hostPath = "/dev/dri";
          isReadOnly = false;
        };
        # # Mount SOPS secrets into the container
        # "/run/secrets-for-users" = {
        #   hostPath = "/run/secrets-for-users";
        #   isReadOnly = true;
        # };
        # Mount jellyfin-specific secrets
        "/run/secrets" = {
          hostPath = "/run/secrets";
          isReadOnly = true;
        };
      };

      allowedDevices = [
        # Give the container R/W access to render devices
        {
          node = hostConfig.hostSpec.gpu.renderDevice;
          modifier = "rwm";
        }
        {
          node = hostConfig.hostSpec.gpu.cardDevice;
          modifier = "rwm";
        }
      ];

      privateNetwork = true;
      hostBridge = net.bridge;
      localAddress = "${net.containerIP}/${net.cidr}";

      # Increase tmpfs size for Jellyfin's temporary files so we can build the binary
      tmpfs = [
        "/tmp:size=4G"
      ];

      forwardPorts = [
        {
          hostPort = 8096;
          containerPort = 8096;
        }
      ];

      config = lib.mkMerge [
        (lib.custom.mkContainerBaseConfig net)
        {
          imports = [ declarativeJellyfinModule ];

          environment.sessionVariables = {
            LIBVA_DRIVER_NAME = "iHD";
          };

          hardware.graphics = {
            enable = true;
            extraPackages = hostConfig.hardware.graphics.extraPackages;
          };

          services.declarative-jellyfin = {
            enable = true;
            openFirewall = true;
            network = {
              knownProxies = [ net.gatewayIP ];
            };

            # SSO Plugin
            # plugins = [
            #   {
            #     name = "SSO Authentication";
            #     url = "https://github.com/9p4/jellyfin-plugin-sso/releases/download/v3.5.2.4/sso-authentication_3.5.2.4.zip";
            #     version = "3.5.2.4";
            #     sha256 = "sha256:0a4w7radf41h3q6dm7s4lhair7s0325jmqspa089cdbsz0w1cd7h";
            #   }
            # ];

            # Branding for SSO
            # branding = {
            #   loginDisclaimer = ''
            #     Single Sign-On is enabled. Click the SSO button below to log in with your account.
            #   '';
            #   customCss = ''
            #     /* Style the SSO login button */
            #     .ssoButton {
            #       background: linear-gradient(135deg, #667eea 0%, #764ba2 100%) !important;
            #       border: none !important;
            #       border-radius: 6px !important;
            #       color: white !important;
            #       font-weight: 500 !important;
            #       margin-top: 1em !important;
            #       padding: 12px 24px !important;
            #       transition: all 0.2s ease !important;
            #     }
            #
            #     .ssoButton:hover {
            #       transform: translateY(-1px) !important;
            #       box-shadow: 0 4px 12px rgba(102, 126, 234, 0.4) !important;
            #     }
            #
            #     /* Hide manual login form elements if desired */
            #     #loginPage .padded-left,
            #     #loginPage .padded-right {
            #       text-align: center !important;
            #     }
            #   '';
            # };

            libraries = {
              Movies = {
                enabled = true;
                contentType = "movies";
                pathInfos = [ "/media/movies" ];
              };
              TVShows = {
                enabled = true;
                contentType = "tvshows";
                pathInfos = [ "/media/tvshows" ];
              };
            };

            # Create users from hostSpec.services.jellyfin.users with SOPS passwords
            users = lib.mapAttrs (username: userConfig: {
              permissions.isAdministrator = userConfig.isAdmin;
              hashedPasswordFile = hostConfig.sops.secrets."jellyfin-passwords/${username}".path;
              mutable = false;
            }) hostConfig.hostSpec.services.jellyfin.users;

            encoding = {
              enableHardwareEncoding = true;
              hardwareAccelerationType = "qsv";
              qsvDevice = hostConfig.hostSpec.gpu.renderDevice;
              enableDecodingColorDepth10Hevc = true;
              allowHevcEncoding = true;
              allowAv1Encoding = false; # N100 doesn't support AV1 encoding
              hardwareDecodingCodecs = [
                "h264"
                "hevc"
                "mpeg2video"
                "vc1" # May not work reliably
                "vp9"
                "av1" # Decode only
              ];
            };

            system = {
              trickplayOptions = {
                enableHwAcceleration = true;
                enableHwEncoding = true;
              };
            };
          };

          # Create media group inside container
          users.groups.media = {
            gid = 5000;
          };

          # Add jellyfin user to video and render groups for hardware acceleration
          users.users.jellyfin.extraGroups = [
            "video"
            "render"
            "media"
          ];
        }
      ];
    };

  # Host systemd configuration for this container
  systemd = lib.mkMerge [
    (lib.custom.mkContainerSystemd "jellyfin" { })
  ];

}
// (
  let
    jellyfinUid = toString config.users.users.jellyfin.uid;
    jellyfinGid = toString config.users.groups.jellyfin.gid;
  in
  lib.custom.mkContainerDirs "jellyfin" [
    {
      path = "/mnt/storage/jellyfin/config";
      owner = jellyfinUid;
      group = jellyfinGid;
      mode = "0755";
    }
    {
      path = "/mnt/storage/jellyfin/cache";
      owner = jellyfinUid;
      group = jellyfinGid;
      mode = "0755";
    }
    {
      path = "/mnt/storage/jellyfin/log";
      owner = jellyfinUid;
      group = jellyfinGid;
      mode = "0755";
    }
    {
      path = "/mnt/storage/jellyfin/metadata";
      owner = jellyfinUid;
      group = jellyfinGid;
      mode = "0755";
    }
    {
      path = "/mnt/storage/jellyfin/playlists";
      owner = jellyfinUid;
      group = jellyfinGid;
      mode = "0755";
    }
    {
      path = "/mnt/storage/jellyfin/plugins";
      owner = jellyfinUid;
      group = jellyfinGid;
      mode = "0755";
    }
    {
      path = "/mnt/storage/jellyfin/root";
      owner = jellyfinUid;
      group = jellyfinGid;
      mode = "0755";
    }
    {
      path = "/mnt/storage/jellyfin/backups";
      owner = jellyfinUid;
      group = jellyfinGid;
      mode = "0755";
    }
    {
      path = "/mnt/storage/jellyfin/wwwroot";
      owner = jellyfinUid;
      group = jellyfinGid;
      mode = "0755";
    }
    # Database directory on root partition
    {
      path = "/var/lib/nixos-containers/jellyfin/var/lib/jellyfin/data";
      owner = jellyfinUid;
      group = jellyfinGid;
      mode = "0755";
    }
    # "Subtitle Edit" directory will remain in container's native filesystem due to space in name
  ]
)
