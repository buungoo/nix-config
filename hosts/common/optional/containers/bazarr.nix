# sudo systemd-run -t --pty -M bazarr --uid=bazarr \
# /run/current-system/sw/bin/bash
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

  hostSpec.networking.containerNetworks.arr.bridge = lib.mkDefault "arr-bridge";
  hostSpec.networking.containerNetworks.arr.subnet = lib.mkDefault "10.0.1.0/24";
  hostSpec.networking.containerNetworks.arr.gateway = lib.mkDefault "10.0.1.1";
  hostSpec.networking.containerNetworks.arr.containers.bazarr = lib.mkDefault 8;

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

          users.users.bazarr = {
            isSystemUser = true;
            group = "bazarr";
            extraGroups = [ "media" ];
            home = "/var/lib/bazarr";
          };
          users.groups.bazarr = { };
          users.groups.media = {
            gid = 5000;
          };

          networking.firewall.allowedTCPPorts = [ 6767 ];

          systemd.tmpfiles.rules = [
            "d /var/lib/bazarr 0755 bazarr bazarr -"
            "d /storage/media 0755 root root -"
            "d /storage/media/movies 0775 bazarr media -"
            "d /storage/media/tvshows 0775 bazarr media -"
          ];
        }
      ];
    };

  systemd = lib.mkMerge [
    (lib.custom.mkContainerSystemd "bazarr" {
      dependsOn = [
        "sonarr"
        "radarr"
      ];
    })
  ];

}
// (lib.custom.mkContainerDirs "bazarr" [
  "/mnt/storage/bazarr"
])
