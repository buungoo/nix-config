# MediaManager in a NixOS container
#
# Provides: custom.services.mediamanager options
# Produces: container definition, reverse proxy registration, tmpfiles
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
  cfg = config.custom.services.mediamanager;
  net = lib.custom.mkContainerNetworkConfig config cfg.network "mediamanager";

  mediamanagerModule = inputs.mediamanager.nixosModules.default;
  mediamanagerPackage = inputs.mediamanager.packages.x86_64-linux.default;

  uid = toString cfg.uid;
  gid = toString cfg.gid;
  mediaGid = 5000;
in
{
  options.custom.services.mediamanager = {
    enable = lib.mkEnableOption "MediaManager container";

    uid = lib.mkOption {
      type = lib.types.int;
      default = 10800;
      description = "UID for mediamanager user on both host and container";
    };

    gid = lib.mkOption {
      type = lib.types.int;
      default = 10800;
      description = "GID for mediamanager group on both host and container";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "mediamanager.${config.hostSpec.domain}";
      description = "FQDN for the MediaManager reverse proxy virtual host";
    };

    network = lib.mkOption {
      type = lib.types.str;
      default = "arr";
      description = "Which containerNetwork to place mediamanager on";
    };

    hostOctet = lib.mkOption {
      type = lib.types.int;
      default = 9;
      description = "Host octet for the container IP in the network subnet.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8000;
      description = "MediaManager HTTP port";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/mediamanager";
      description = "Host path for persistent application and database data";
    };

    rootPath = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/storage/arr";
      description = "Host path to the arr root directory (mounted as /arr in container)";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.custom.mkContainerServiceConfig "mediamanager" { })
      {
        # Create user on host
        users.users.mediamanager = {
          isSystemUser = true;
          group = "mediamanager";
          extraGroups = [ "media" ];
          uid = cfg.uid;
        };
        users.groups.mediamanager.gid = cfg.gid;

        # Register reverse proxy
        custom.reverseProxy.virtualHosts.mediamanager = {
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
          containers.mediamanager = lib.mkDefault cfg.hostOctet;
        };

        # Setup bindmount directories
        systemd.tmpfiles.rules = [
          "d ${cfg.dataDir} 0755 ${uid} ${toString cfg.gid} -"
          "d ${cfg.dataDir}/postgresql 0750 71 71 -"
        ];

        # Container definition
        containers.mediamanager = {
          autoStart = true;
          ephemeral = true;

          bindMounts = {
            "/var/lib/media-manager" = {
              hostPath = cfg.dataDir;
              isReadOnly = false;
            };
            "/var/lib/postgresql" = {
              hostPath = "${cfg.dataDir}/postgresql";
              isReadOnly = false;
            };
            "/arr" = {
              hostPath = cfg.rootPath;
              isReadOnly = false;
            };
          };

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
              imports = [ mediamanagerModule ];

              time.timeZone = "Europe/Stockholm";

              services.media-manager = {
                enable = true;
                package = mediamanagerPackage;
                port = cfg.port;
                host = "0.0.0.0";
                dataDir = "/arr";

                settings.misc = {
                  movie_directory = "/arr/media/movies";
                  tv_directory = "/arr/media/tvshows";
                  torrent_directory = "/arr/torrents";
                  image_directory = "/var/lib/media-manager/images";
                };

                postgres.enable = true;
              };

              # Set TZ so Python tzlocal resolves a named timezone (picklable by apscheduler)
              systemd.services.media-manager.environment.TZ = config.time.timeZone;

              # Container user/group
              users.users.media-manager = {
                isSystemUser = true;
                group = "media-manager";
                extraGroups = [ "media" ];
                uid = cfg.uid;
              };
              users.groups.media-manager.gid = cfg.gid;
              users.groups.media.gid = mediaGid;

              # Open firewall for the web UI
              networking.firewall.allowedTCPPorts = [ cfg.port ];
            }
          ];
        };
      }
    ]
  );
}
