# Mydia media manager in a NixOS container
#
# Provides: custom.services.mydia options
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
  cfg = config.custom.services.mydia;
  net = lib.custom.mkContainerNetworkConfig config cfg.network "mydia";

  mydiaModule = inputs.mydia.nixosModules.default;
  mydiaPackage = inputs.mydia.packages.x86_64-linux.default;

  uid = toString cfg.uid;
  gid = toString cfg.gid;
  mediaGid = 5000;

  sopsFolder = builtins.toString inputs.nix-secrets + "/sops";
in
{
  options.custom.services.mydia = {
    enable = lib.mkEnableOption "Mydia media manager container";

    uid = lib.mkOption {
      type = lib.types.int;
      default = 10800;
      description = "UID for mydia user on both host and container";
    };

    gid = lib.mkOption {
      type = lib.types.int;
      default = 10800;
      description = "GID for mydia group on both host and container";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "mydia.${config.hostSpec.domain}";
      description = "FQDN for the Mydia reverse proxy virtual host";
    };

    network = lib.mkOption {
      type = lib.types.str;
      default = "arr";
      description = "Which containerNetwork to place mydia on";
    };

    hostOctet = lib.mkOption {
      type = lib.types.int;
      default = 9;
      description = "Host octet for the container IP in the network subnet.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 4000;
      description = "Mydia HTTP port";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/mydia";
      description = "Host path for application data";
    };

    rootPath = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/storage/arr";
      description = "Host path to the arr root directory (mounted as /arr in container)";
    };

    mediaLibraries = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "/arr/media/movies"
        "/arr/media/tvshows"
      ];
      description = "Media library paths inside the container that Mydia needs read access to";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.custom.mkContainerServiceConfig "mydia" { })
      {
        # Create user on host
        users.users.mydia = {
          isSystemUser = true;
          group = "mydia";
          extraGroups = [ "media" ];
          uid = cfg.uid;
        };
        users.groups.mydia.gid = cfg.gid;

        # Register reverse proxy
        custom.reverseProxy.virtualHosts.mydia = {
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
          containers.mydia = lib.mkDefault cfg.hostOctet;
        };

        # Setup bindmount directories
        systemd.tmpfiles.rules = [
          "d ${cfg.dataDir} 0755 ${uid} ${toString cfg.gid} -"
        ];

        # Fetch secrets
        sops.secrets."mydia/secret-key-base" = {
          sopsFile = "${sopsFolder}/shared.yaml";
          owner = "root";
          group = "root";
          mode = "0400";
        };

        # Container definition
        containers.mydia = {
          autoStart = true;
          ephemeral = true;

          bindMounts = {
            "/var/lib/mydia" = {
              hostPath = cfg.dataDir;
              isReadOnly = false;
            };
            "/arr" = {
              hostPath = cfg.rootPath;
              isReadOnly = false;
            };
            "/run/secrets" = {
              hostPath = "/run/secrets";
              isReadOnly = true;
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
              imports = [ mydiaModule ];

              services.mydia = {
                enable = true;
                package = mydiaPackage;
                port = cfg.port;
                host = cfg.domain;
                listenAddress = "0.0.0.0";
                openFirewall = true;
                secretKeyBaseFile = "/run/secrets/mydia/secret-key-base";
                mediaLibraries = cfg.mediaLibraries;
              };

              # Container user/group
              users.users.mydia = {
                isSystemUser = true;
                group = "mydia";
                extraGroups = [ "media" ];
                home = "/var/lib/mydia";
                uid = cfg.uid;
              };
              users.groups.mydia.gid = cfg.gid;
              users.groups.media.gid = mediaGid;
            }
          ];
        };
      }
    ]
  );
}
