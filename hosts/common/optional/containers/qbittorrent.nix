# sudo systemd-run -t --pty -M qbittorrent --uid=qbittorrent \
#     /run/current-system/sw/bin/bash
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
  hostSpec.networking.containerNetworks.arr.containers.qbittorrent = lib.mkDefault 7;

  containers.qbittorrent =
    let
      net = lib.custom.mkContainerNetworkConfig config "arr" "qbittorrent";
      hostConfig = config;
    in
    {

      autoStart = true;

      bindMounts = {
        "/var/lib/qbittorrent" = {
          hostPath = "/mnt/storage/qbittorrent";
          isReadOnly = false;
        };
        "/storage" = {
          hostPath = "/mnt/storage";
          isReadOnly = false;
        };
        "/run/secrets" = {
          hostPath = "/run/secrets";
          isReadOnly = true;
        };
      };

      privateNetwork = true;
      hostBridge = net.bridge;
      localAddress = "${net.containerIP}/${net.cidr}";

      forwardPorts = [
        {
          hostPort = 8080;
          containerPort = 8080;
        }
      ];

      config = lib.mkMerge [
        (lib.custom.mkContainerBaseConfig net)
        {
          # Ensure local traffic bypasses VPN
          networking.localCommands = ''
            # Add routes for local networks to bypass VPN
            ip route add 10.0.0.0/8 via ${net.gatewayIP} dev eth0 table main priority 100
            ip route add 192.168.0.0/16 via ${net.gatewayIP} dev eth0 table main priority 100
            ip route add 172.16.0.0/12 via ${net.gatewayIP} dev eth0 table main priority 100
          '';

          networking.wg-quick.interfaces.wg0 = {
            configFile = "/run/secrets/protonvpn/wg-config";
            autostart = true;
          };

          # Open firewall for qBittorrent web UI
          networking.firewall = {
            allowedTCPPorts = [ 8080 ];
          };

          systemd.services.qbittorrent = {
            description = "qBittorrent daemon";
            after = [
              "network.target"
              "wg-quick-wg0.service"
            ];
            wants = [ "wg-quick-wg0.service" ];
            wantedBy = [ "multi-user.target" ];

            serviceConfig = {
              Type = "exec";
              User = "qbittorrent";
              Group = "media";
              UMask = "0002";
              ExecStart = "${pkgs.qbittorrent-nox}/bin/qbittorrent-nox --webui-port=8080";
              Restart = "on-failure";
              RestartSec = "5s";
            };
          };

          users.users.qbittorrent = {
            isSystemUser = true;
            uid = lib.mkForce 5000;
            group = "media";
            home = "/var/lib/qbittorrent";
            createHome = true;
          };
          users.groups.qbittorrent = { };
          users.groups.media = {
            gid = 5000;
          };

          environment.systemPackages = with pkgs; [
            qbittorrent-nox
          ];

          systemd.tmpfiles.rules = [
            "d /storage/downloads 2775 qbittorrent media -"
            "d /storage/downloads/incomplete 2775 qbittorrent media -"
            "d /storage/torrents 2775 qbittorrent media -"
            "d /storage/torrents/movies 2775 qbittorrent media -"
            "d /storage/torrents/tv 2775 qbittorrent media -"
            "d /storage/torrents/music 2775 qbittorrent media -"
            "d /storage/torrents/books 2775 qbittorrent media -"
          ];
        }
      ];
    };

  systemd = lib.mkMerge [
    (lib.custom.mkContainerSystemd "qbittorrent" { })
  ];

}
// (lib.custom.mkContainerDirs "qbittorrent" [
  {
    path = "/mnt/storage/qbittorrent";
    owner = "5000";
    group = "5000";
    mode = "0755";
  }
  # Use shared media group (GID 5000) for all media services
  {
    path = "/mnt/storage/downloads";
    owner = "5000";
    group = "5000";
    mode = "0775";
  }
  {
    path = "/mnt/storage/downloads/incomplete";
    owner = "5000";
    group = "5000";
    mode = "0775";
  }
  {
    path = "/mnt/storage/downloads/complete";
    owner = "5000";
    group = "5000";
    mode = "0775";
  }
  {
    path = "/mnt/storage/downloads/complete/movies";
    owner = "5000";
    group = "5000";
    mode = "0775";
  }
  {
    path = "/mnt/storage/downloads/complete/tv";
    owner = "5000";
    group = "5000";
    mode = "0775";
  }
  # TRaSH guides torrents structure
  {
    path = "/mnt/storage/torrents";
    owner = "5000";
    group = "5000";
    mode = "0775";
  }
  {
    path = "/mnt/storage/torrents/movies";
    owner = "5000";
    group = "5000";
    mode = "0775";
  }
  {
    path = "/mnt/storage/torrents/tv";
    owner = "5000";
    group = "5000";
    mode = "0775";
  }
  {
    path = "/mnt/storage/torrents/music";
    owner = "5000";
    group = "5000";
    mode = "0775";
  }
  {
    path = "/mnt/storage/torrents/books";
    owner = "5000";
    group = "5000";
    mode = "0775";
  }
])
