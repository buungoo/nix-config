# Radarr Configuration Steps (http://10.0.1.5:7878)
#	1. Settings → Media Management → Root Folders
#		Add: /mnt/storage/media/movies
#	2. Settings → Download Clients → Add qBittorrent
#		Host: 10.0.1.7, Port: 8080, Category: movies
#	3. Settings → Media Management
#		Enable: Rename Movies, Replace Illegal Characters
#		Leave naming formats default (Recyclarr will optimize)
#	4. Movies → Import Existing Movies
#		Select root folder and import existing library
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

  users.users.radarr = {
    isSystemUser = true;
    group = "radarr";
    extraGroups = [ "media" ];
    uid = 275;
  };
  users.groups.radarr = {
    gid = 275;
  };
  users.groups.media = {
    gid = 5000;
  };

  hostSpec.networking.containerNetworks.arr.bridge = lib.mkDefault "arr-bridge";
  hostSpec.networking.containerNetworks.arr.subnet = lib.mkDefault "10.0.1.0/24";
  hostSpec.networking.containerNetworks.arr.gateway = lib.mkDefault "10.0.1.1";
  hostSpec.networking.containerNetworks.arr.containers.radarr = lib.mkDefault 5;

  containers.radarr =
    let
      net = lib.custom.mkContainerNetworkConfig config "arr" "radarr";
    in
    {
      autoStart = true;

      bindMounts = {
        "/var/lib/radarr" = {
          hostPath = "/mnt/storage/radarr";
          isReadOnly = false;
        };
        "/storage" = {
          hostPath = "/mnt/storage";
          isReadOnly = false;
        };
      };

      privateNetwork = true;
      hostBridge = net.bridge;
      localAddress = "${net.containerIP}/${net.cidr}";

      forwardPorts = [
        {
          hostPort = 7878;
          containerPort = 7878;
        }
      ];

      config = lib.mkMerge [
        (lib.custom.mkContainerBaseConfig net)
        {
          services.radarr = {
            enable = true;
            openFirewall = true;
            dataDir = "/var/lib/radarr";
          };

          users.groups.media = {
            gid = 5000;
          };

          users.users.radarr.extraGroups = [ "media" ];

          systemd.tmpfiles.rules = [
            "d /var/lib/radarr 0755 radarr media -"
            "d /storage/downloads 0775 radarr media -"
            "d /storage/torrents 0775 radarr media -"
            "d /storage/media/movies 0775 radarr media -"
          ];
        }
      ];
    };

  systemd = lib.mkMerge [
    (lib.custom.mkContainerSystemd "radarr" { })
  ];

}
// (lib.custom.mkContainerDirs "radarr" [
  "/mnt/storage/radarr"
  {
    path = "/mnt/storage/media/movies";
    owner = "275";
    group = "5000";
    mode = "0775";
  }
])
