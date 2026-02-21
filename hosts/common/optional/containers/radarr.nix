# Radarr Configuration Steps (http://10.0.1.5:7878)
#	1. Settings → Media Management → Root Folders
#		Add: /arr/media/movies
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

let
  uid = 10300;
  gid = 10300;
  mediaGid = 5000;
  net = lib.custom.mkContainerNetworkConfig config "arr" "radarr";
in
{
  imports = [
    (./networking.nix)
  ];

  # --- Host user/group (matches container for bind mount ownership) ---
  users.users.radarr = {
    isSystemUser = true;
    group = "radarr";
    extraGroups = [ "media" ];
    inherit uid;
  };
  users.groups.radarr.gid = gid;
  users.groups.media.gid = mediaGid;

  hostSpec.networking.containerNetworks.arr.bridge = lib.mkDefault "arr-bridge";
  hostSpec.networking.containerNetworks.arr.subnet = lib.mkDefault "10.0.1.0/24";
  hostSpec.networking.containerNetworks.arr.gateway = lib.mkDefault "10.0.1.1";
  hostSpec.networking.containerNetworks.arr.containers.radarr = lib.mkDefault 5;

  custom.reverseProxy.virtualHosts.radarr = {
    domain = "radarr.${config.hostSpec.domain}";
    backendHost = net.containerIP;
    backendPort = 7878;
    backendSSL = false;
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/radarr 0755 ${toString uid} ${toString gid} -"
    "d /mnt/storage/arr/media/movies 0775 ${toString uid} ${toString mediaGid} -"
  ];

  containers.radarr =
    {
      autoStart = true;
      ephemeral = true;

      bindMounts = {
        "/var/lib/radarr" = {
          hostPath = "/var/lib/radarr";
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
          hostPort = 7878;
          containerPort = 7878;
        }
      ];

      config = lib.mkMerge [
        (lib.custom.mkContainerBaseConfig (net // { inherit (config.hostSpec) stateVersion; }))
        {
          services.radarr = {
            enable = true;
            openFirewall = true;
            dataDir = "/var/lib/radarr";
          };

          # --- Container user/group (matches host) ---
          # mkForce needed: services.radarr hardcodes uid 275
          users.users.radarr = {
            isSystemUser = true;
            uid = lib.mkForce uid;
            extraGroups = [ "media" ];
          };
          users.groups.radarr.gid = lib.mkForce gid;
          users.groups.media.gid = mediaGid;

          systemd.tmpfiles.rules = [
            "d /var/lib/radarr 0755 ${toString uid} ${toString gid} -"
            "d /arr/media/movies 0775 ${toString uid} ${toString mediaGid} -"
          ];
        }
      ];
    };

  systemd.services."container@radarr" = {
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "systemd-tmpfiles-setup.service"
    ];
  };
}
