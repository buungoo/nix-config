# Sonarr Configuration Steps (http://10.0.1.4:8989)
#	1. Settings → Media Management → Root Folders
#		Add: /arr/media/tvshows
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

let
  uid = 10200;
  gid = 10200;
  mediaGid = 5000;
  net = lib.custom.mkContainerNetworkConfig config "arr" "sonarr";
in
{
  imports = [
    (./networking.nix)
  ];

  # --- Host user/group (matches container for bind mount ownership) ---
  users.users.sonarr = {
    isSystemUser = true;
    group = "sonarr";
    extraGroups = [ "media" ];
    inherit uid;
  };
  users.groups.sonarr.gid = gid;
  users.groups.media.gid = mediaGid;

  hostSpec.networking.containerNetworks.arr.bridge = lib.mkDefault "arr-bridge";
  hostSpec.networking.containerNetworks.arr.subnet = lib.mkDefault "10.0.1.0/24";
  hostSpec.networking.containerNetworks.arr.gateway = lib.mkDefault "10.0.1.1";
  hostSpec.networking.containerNetworks.arr.containers.sonarr = lib.mkDefault 4;

  custom.reverseProxy.virtualHosts.sonarr = {
    domain = "sonarr.${config.hostSpec.domain}";
    backendHost = net.containerIP;
    backendPort = 8989;
    backendSSL = false;
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/sonarr 0755 ${toString uid} ${toString gid} -"
    "d /mnt/storage/arr/media/tv 0775 ${toString uid} ${toString mediaGid} -"
  ];

  containers.sonarr =
    {
      autoStart = true;
      ephemeral = true;

      bindMounts = {
        "/var/lib/sonarr" = {
          hostPath = "/var/lib/sonarr";
          isReadOnly = false;
        };
        "/arr" = {
          hostPath = "/mnt/storage/arr";
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

          # --- Container user/group (matches host) ---
          # mkForce needed: services.sonarr hardcodes uid 274
          users.users.sonarr = {
            isSystemUser = true;
            uid = lib.mkForce uid;
            extraGroups = [ "media" ];
          };
          users.groups.sonarr.gid = lib.mkForce gid;
          users.groups.media.gid = mediaGid;

          systemd.tmpfiles.rules = [
            "d /var/lib/sonarr 0755 ${toString uid} ${toString gid} -"
            "d /arr/media/tv 0775 ${toString uid} ${toString mediaGid} -"
          ];
        }
      ];
    };

  systemd.services."container@sonarr" = {
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "systemd-tmpfiles-setup.service"
    ];
  };
}
