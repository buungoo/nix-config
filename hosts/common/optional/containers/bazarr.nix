# sudo systemd-run -t --pty -M bazarr --uid=bazarr \
# /run/current-system/sw/bin/bash
{
  config,
  pkgs,
  lib,
  ...
}:

let
  uid = 10500;
  gid = 10500;
  mediaGid = 5000;
in
{
  imports = [
    (./networking.nix)
  ];

  # --- Host user/group (matches container for bind mount ownership) ---
  users.users.bazarr = {
    isSystemUser = true;
    group = "bazarr";
    extraGroups = [ "media" ];
    inherit uid;
  };
  users.groups.bazarr.gid = gid;
  users.groups.media.gid = mediaGid;

  hostSpec.networking.containerNetworks.arr.bridge = lib.mkDefault "arr-bridge";
  hostSpec.networking.containerNetworks.arr.subnet = lib.mkDefault "10.0.1.0/24";
  hostSpec.networking.containerNetworks.arr.gateway = lib.mkDefault "10.0.1.1";
  hostSpec.networking.containerNetworks.arr.containers.bazarr = lib.mkDefault 8;

  systemd.tmpfiles.rules = [
    "d /mnt/storage/bazarr 0755 ${toString uid} ${toString gid} -"
  ];

  containers.bazarr =
    let
      net = lib.custom.mkContainerNetworkConfig config "arr" "bazarr";
    in
    {
      autoStart = true;

      bindMounts = {
        "/var/lib/bazarr" = {
          hostPath = "/mnt/storage/bazarr";
          isReadOnly = false;
        };
        # Bazarr only needs media access (for subtitles), not torrents/downloads
        "/media" = {
          hostPath = "/mnt/storage/arr/media";
          isReadOnly = false;
        };
      };

      privateNetwork = true;
      hostBridge = net.bridge;
      localAddress = "${net.containerIP}/${net.cidr}";

      forwardPorts = [
        {
          hostPort = 6767;
          containerPort = 6767;
        }
      ];

      config = lib.mkMerge [
        (lib.custom.mkContainerBaseConfig net)
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
              # Reduce stop timeout to avoid long shutdown delays
              TimeoutStopSec = "10s";
              # Send SIGTERM for graceful shutdown, then SIGKILL after timeout
              KillMode = "mixed";
              KillSignal = "SIGTERM";
            };
          };

          # --- Container user/group (matches host) ---
          users.users.bazarr = {
            isSystemUser = true;
            inherit uid;
            group = "bazarr";
            extraGroups = [ "media" ];
            home = "/var/lib/bazarr";
          };
          users.groups.bazarr.gid = gid;
          users.groups.media.gid = mediaGid;

          networking.firewall.allowedTCPPorts = [ 6767 ];

          systemd.tmpfiles.rules = [
            "d /var/lib/bazarr 0755 ${toString uid} ${toString gid} -"
            "d /media/movies 0775 ${toString uid} ${toString mediaGid} -"
            "d /media/tvshows 0775 ${toString uid} ${toString mediaGid} -"
          ];
        }
      ];
    };

  systemd.services."container@bazarr" = {
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
