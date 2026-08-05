{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.custom.services.bazarr;
  net = lib.custom.mkContainerNetworkConfig config cfg.network "bazarr";

  uid = toString cfg.uid;
  gid = toString cfg.gid;
  mediaGid = 5000;
in
{
  options.custom.services.bazarr = {
    enable = lib.mkEnableOption "Bazarr subtitle manager container";

    uid = lib.mkOption {
      type = lib.types.int;
      default = 10500;
      description = "UID for bazarr user on both host and container";
    };

    gid = lib.mkOption {
      type = lib.types.int;
      default = 10500;
      description = "GID for bazarr group on both host and container";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "bazarr.${config.hostSpec.domain}";
      description = "FQDN for the Bazarr reverse proxy virtual host";
    };

    network = lib.mkOption {
      type = lib.types.str;
      default = "arr";
      description = "Which containerNetwork to place bazarr on";
    };

    hostOctet = lib.mkOption {
      type = lib.types.int;
      default = 8;
      description = "Host octet for the container IP in the network subnet.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 6767;
      description = "Bazarr HTTP port";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/bazarr";
      description = "Host path for persistent Bazarr application data";
    };

    mediaMounts = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        "/arr/media/movies" = "/mnt/storage/arr/media/movies";
        "/arr/media/tv" = "/mnt/storage/arr/media/tv";
      };
      description = "Container path -> host path mappings for writable media directories.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.custom.mkContainerServiceConfig "bazarr" {
        dependsOn = [
          "sonarr"
          "radarr"
        ];
      })
      {
        users.users.bazarr = {
          isSystemUser = true;
          group = "bazarr";
          extraGroups = [ "media" ];
          uid = cfg.uid;
        };
        users.groups.bazarr.gid = cfg.gid;

        custom.reverseProxy.virtualHosts.bazarr = {
          domain = cfg.domain;
          backendHost = net.containerIP;
          backendPort = cfg.port;
          backendSSL = false;
        };

        hostSpec.networking.containerNetworks.${cfg.network} = {
          bridge = lib.mkDefault "${cfg.network}-bridge";
          subnet = lib.mkDefault "10.0.1.0/24";
          gateway = lib.mkDefault "10.0.1.1";
          containers.bazarr = lib.mkDefault cfg.hostOctet;
        };

        # Media dirs (/arr/media/{movies,tv}) are owned by sonarr/radarr;
        # do not redeclare them here or tmpfiles will fight over ownership.
        systemd.tmpfiles.rules = [
          "d ${cfg.dataDir} 0755 ${uid} ${gid} -"
        ];

        containers.bazarr = {
          autoStart = true;
          ephemeral = true;

          bindMounts = {
            "/var/lib/bazarr" = {
              hostPath = cfg.dataDir;
              isReadOnly = false;
            };
          }
          // (lib.mapAttrs (_: hostPath: {
            inherit hostPath;
            isReadOnly = false;
          }) cfg.mediaMounts);

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
              systemd.services.bazarr = {
                enable = true;
                description = "Bazarr subtitle manager";
                after = [ "network.target" ];
                wantedBy = [ "multi-user.target" ];

                serviceConfig = {
                  Type = "exec";
                  User = "bazarr";
                  Group = "bazarr";
                  ExecStart = "${pkgs.bazarr}/bin/bazarr --no-update --config /var/lib/bazarr";
                  Restart = "on-failure";
                  WorkingDirectory = "/var/lib/bazarr";
                  TimeoutStopSec = "10s";
                  KillMode = "mixed";
                  KillSignal = "SIGTERM";
                };
              };

              users.users.bazarr = {
                isSystemUser = true;
                uid = cfg.uid;
                group = "bazarr";
                extraGroups = [ "media" ];
                home = "/var/lib/bazarr";
              };
              users.groups.bazarr.gid = cfg.gid;
              users.groups.media.gid = mediaGid;

              networking.firewall.allowedTCPPorts = [ cfg.port ];
            }
          ];
        };
      }
    ]
  );
}
