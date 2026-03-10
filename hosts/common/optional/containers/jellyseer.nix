# Jellyseer request management container
{
  config,
  pkgs,
  lib,
  ...
}:

let
  uid = 10600;
  gid = 10600;
in
{
  imports = [
    (./networking.nix)
  ];

  # --- Host user/group (matches container for bind mount ownership) ---
  users.users.jellyseerr = {
    isSystemUser = true;
    group = "jellyseerr";
    inherit uid;
  };
  users.groups.jellyseerr.gid = gid;

  hostSpec.networking.containerNetworks.arr.bridge = lib.mkDefault "arr-bridge";
  hostSpec.networking.containerNetworks.arr.subnet = lib.mkDefault "10.0.1.0/24";
  hostSpec.networking.containerNetworks.arr.gateway = lib.mkDefault "10.0.1.1";
  hostSpec.networking.containerNetworks.arr.containers.jellyseer = lib.mkDefault 3;

  systemd.tmpfiles.rules = [
    "d /var/lib/jellyseerr 0755 ${toString uid} ${toString gid} -"
  ];

  containers.jellyseer =
    let
      net = lib.custom.mkContainerNetworkConfig config "arr" "jellyseer";
    in
    {
      autoStart = true;
      ephemeral = true;

      bindMounts = {
        "/var/lib/jellyseerr" = {
          hostPath = "/var/lib/jellyseerr";
          isReadOnly = false;
        };
        "/media/movies" = {
          hostPath = "/mnt/storage/arr/media/movies";
          isReadOnly = true;
        };
        "/media/tv" = {
          hostPath = "/mnt/storage/arr/media/tv";
          isReadOnly = true;
        };
      };

      privateNetwork = true;
      hostBridge = net.bridge;
      localAddress = "${net.containerIP}/${net.cidr}";

      forwardPorts = [
        {
          hostPort = 5055;
          containerPort = 5055;
        }
      ];

      config = lib.mkMerge [
        (lib.custom.mkContainerBaseConfig (net // { inherit (config.hostSpec) stateVersion; }))
        {
          systemd.services.jellyseerr = {
            enable = true;
            description = "Jellyseerr request management";
            after = [ "network.target" ];
            wantedBy = [ "multi-user.target" ];

            serviceConfig = {
              Type = "exec";
              User = "jellyseerr";
              Group = "jellyseerr";
              ExecStart = "${pkgs.jellyseerr}/bin/jellyseerr";
              Restart = "on-failure";
              WorkingDirectory = "/var/lib/jellyseerr";
              Environment = [
                "PORT=5055"
                "CONFIG_DIRECTORY=/var/lib/jellyseerr"
              ];
            };
          };

          # --- Container user/group (matches host) ---
          users.users.jellyseerr = {
            isSystemUser = true;
            inherit uid;
            group = "jellyseerr";
            home = "/var/lib/jellyseerr";
          };
          users.groups.jellyseerr.gid = gid;

          networking.firewall.allowedTCPPorts = [ 5055 ];

          systemd.tmpfiles.rules = [
            "d /var/lib/jellyseerr 0755 ${toString uid} ${toString gid} -"
          ];
        }
      ];
    };

  systemd.services."container@jellyseer" = {
    wants = [
      "network-online.target"
      "container@sonarr.service"
      "container@radarr.service"
    ];
    after = [
      "network-online.target"
      "systemd-tmpfiles-setup.service"
      "container@sonarr.service"
      "container@radarr.service"
    ];
  };
}
