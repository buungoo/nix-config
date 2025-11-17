# Sonarr Configuration Steps (http://10.0.1.4:8989)
#	1. Settings → Media Management → Root Folders
#		Add: /mnt/storage/media/tvshows
#	2. Settings → Download Clients → Add qBittorrent
#		Host: 10.0.1.7, Port: 8080, Category: tv
#	3. Settings → Media Management
#		Enable: Rename Episodes, Replace Illegal Characters
#		Leave naming formats default (Recyclarr will optimize)
#	4. Series → Import Existing Series
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

  users.users.sonarr = {
    isSystemUser = true;
    group = "sonarr";
    extraGroups = [ "media" ];
    uid = 274;
  };
  users.groups.sonarr = {
    gid = 274;
  };
  users.groups.media = {
    gid = 5000;
  };

  hostSpec.networking.containerNetworks.arr.bridge = lib.mkDefault "arr-bridge";
  hostSpec.networking.containerNetworks.arr.subnet = lib.mkDefault "10.0.1.0/24";
  hostSpec.networking.containerNetworks.arr.gateway = lib.mkDefault "10.0.1.1";
  hostSpec.networking.containerNetworks.arr.containers.sonarr = lib.mkDefault 4;

  containers.sonarr =
    let
      net = lib.custom.mkContainerNetworkConfig config "arr" "sonarr";
    in
    {
      autoStart = true;

      bindMounts = {
        "/var/lib/sonarr" = {
          hostPath = "/mnt/storage/sonarr";
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
          hostPort = 8989;
          containerPort = 8989;
        }
      ];

      config = lib.mkMerge [
        (lib.custom.mkContainerBaseConfig net)
        {
          services.sonarr = {
            enable = true;
            openFirewall = true;
            dataDir = "/var/lib/sonarr";

            settings = {
              MediaManagement = {
                AutoRenameFolders = true;
                CopyUsingHardlinks = true; # Critical for hardlinks
                EnableMediaInfo = true;
                RecycleBin = "";
                SetPermissionsLinux = false;
              };

              DownloadClient = {
                EnableCompletedDownloadHandling = true;
                RemoveCompletedDownloads = false; # Preserve
              };
            };
          };

          users.groups.media = {
            gid = 5000;
          };

          users.users.sonarr.extraGroups = [ "media" ];

          systemd.tmpfiles.rules = [
            "d /var/lib/sonarr 0755 sonarr media -"
            "d /storage/downloads 0775 sonarr media -"
            "d /storage/torrents 0775 sonarr media -"
            "d /storage/media/tvshows 0775 sonarr media -"
          ];
        }
      ];
    };

  systemd = lib.mkMerge [
    (lib.custom.mkContainerSystemd "sonarr" { })
  ];

}
// (lib.custom.mkContainerDirs "sonarr" [
  "/mnt/storage/sonarr"
  {
    path = "/mnt/storage/media/tvshows";
    owner = "274";
    group = "5000";
    mode = "0775";
  }
])
