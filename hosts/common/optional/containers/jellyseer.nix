# Jellyseer request management container
{
  config,
  pkgs,
  lib,
  ...
}:

{
  imports = [
    (./networking.nix)
  ];

  users.users.jellyseerr = {
    isSystemUser = true;
    group = "jellyseerr";
    uid = 276;
  };
  users.groups.jellyseerr = {
    gid = 276;
  };

  hostSpec.networking.containerNetworks.arr.bridge = lib.mkDefault "arr-bridge";
  hostSpec.networking.containerNetworks.arr.subnet = lib.mkDefault "10.0.1.0/24";
  hostSpec.networking.containerNetworks.arr.gateway = lib.mkDefault "10.0.1.1";
  hostSpec.networking.containerNetworks.arr.containers.jellyseer = lib.mkDefault 3;

  containers.jellyseer =
    let
      net = lib.custom.mkContainerNetworkConfig config "arr" "jellyseer";
    in
    {
      autoStart = true;

      bindMounts = {
        "/var/lib/jellyseerr" = {
          hostPath = "/mnt/storage/jellyseer";
          isReadOnly = false;
        };
        "/media/movies" = {
          hostPath = "/mnt/storage/media/movies";
          isReadOnly = true;
        };
        "/media/tvshows" = {
          hostPath = "/mnt/storage/media/tvshows";
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
        (lib.custom.mkContainerBaseConfig net)
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

          users.users.jellyseerr = {
            isSystemUser = true;
            group = "jellyseerr";
            home = "/var/lib/jellyseerr";
          };
          users.groups.jellyseerr = { };

          networking.firewall.allowedTCPPorts = [ 5055 ];

          systemd.tmpfiles.rules = [
            "d /var/lib/jellyseerr 0755 jellyseerr jellyseerr -"
            "d /media 0755 root root -"
          ];
        }
      ];
    };

  systemd = lib.mkMerge [
    (lib.custom.mkContainerSystemd "jellyseer" {
      dependsOn = [
        "sonarr"
        "radarr"
      ];
    })
  ];

}
// (lib.custom.mkContainerDirs "jellyseer" [
  "/mnt/storage/jellyseer"
])
