# sudo systemd-run -t --pty -M qbittorrent --uid=qbittorrent \
#     /run/current-system/sw/bin/bash
#
# TODO: Configure qBittorrent categories to match torrent directory structure:
#   movies  → save path: /arr/torrents/movies/complete,  temp: /arr/torrents/movies/incomplete
#   tv      → save path: /arr/torrents/tv/complete,      temp: /arr/torrents/tv/incomplete
#   music   → save path: /arr/torrents/music/complete,   temp: /arr/torrents/music/incomplete
#   books   → save path: /arr/torrents/books/complete,   temp: /arr/torrents/books/incomplete
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

let
  uid = 10400;
  gid = 10400;
  mediaGid = 5000;
in
{
  imports = [
    (./networking.nix)
  ];

  # ProtonVPN WireGuard configuration for qbittorrent VPN tunnel
  sops.secrets."protonvpn/wg-config" = {
    sopsFile = "${builtins.toString inputs.nix-secrets}/sops/${config.hostSpec.hostName}.yaml";
    owner = "root";
    group = "root";
    mode = "0644";
  };

  # --- Host user/group (matches container for bind mount ownership) ---
  users.users.qbittorrent = {
    isSystemUser = true;
    group = "qbittorrent";
    extraGroups = [ "media" ];
    inherit uid;
  };
  users.groups.qbittorrent.gid = gid;
  users.groups.media.gid = mediaGid;

  hostSpec.networking.containerNetworks.arr.bridge = lib.mkDefault "arr-bridge";
  hostSpec.networking.containerNetworks.arr.subnet = lib.mkDefault "10.0.1.0/24";
  hostSpec.networking.containerNetworks.arr.gateway = lib.mkDefault "10.0.1.1";
  hostSpec.networking.containerNetworks.arr.containers.qbittorrent = lib.mkDefault 7;

  systemd.tmpfiles.rules = [
    "d /var/lib/qbittorrent 0755 ${toString uid} ${toString gid} -"

    "d /mnt/storage/arr/torrents 2775 ${toString uid} ${toString mediaGid} -"
    "d /mnt/storage/arr/torrents/movies 2775 ${toString uid} ${toString mediaGid} -"
    "d /mnt/storage/arr/torrents/tv 2775 ${toString uid} ${toString mediaGid} -"
    "d /mnt/storage/arr/torrents/music 2775 ${toString uid} ${toString mediaGid} -"
    "d /mnt/storage/arr/torrents/books 2775 ${toString uid} ${toString mediaGid} -"
    "d /mnt/storage/arr/torrents/movies/complete 2775 ${toString uid} ${toString mediaGid} -"
    "d /mnt/storage/arr/torrents/movies/incomplete 2775 ${toString uid} ${toString mediaGid} -"
    "d /mnt/storage/arr/torrents/tv/complete 2775 ${toString uid} ${toString mediaGid} -"
    "d /mnt/storage/arr/torrents/tv/incomplete 2775 ${toString uid} ${toString mediaGid} -"
    "d /mnt/storage/arr/torrents/music/complete 2775 ${toString uid} ${toString mediaGid} -"
    "d /mnt/storage/arr/torrents/music/incomplete 2775 ${toString uid} ${toString mediaGid} -"
    "d /mnt/storage/arr/torrents/books/complete 2775 ${toString uid} ${toString mediaGid} -"
    "d /mnt/storage/arr/torrents/books/incomplete 2775 ${toString uid} ${toString mediaGid} -"
  ];

  containers.qbittorrent =
    let
      net = lib.custom.mkContainerNetworkConfig config "arr" "qbittorrent";
      hostConfig = config;
    in
    {

      autoStart = true;
      ephemeral = true;

      bindMounts = {
        "/var/lib/qbittorrent" = {
          hostPath = "/var/lib/qbittorrent";
          isReadOnly = false;
        };
        "/arr" = {
          hostPath = "/mnt/storage/arr";
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

          # --- Container user/group (matches host) ---
          users.users.qbittorrent = {
            isSystemUser = true;
            inherit uid;
            group = "qbittorrent";
            extraGroups = [ "media" ];
            home = "/var/lib/qbittorrent";
            createHome = true;
          };
          users.groups.qbittorrent.gid = gid;
          users.groups.media.gid = mediaGid;

          environment.systemPackages = with pkgs; [
            qbittorrent-nox
          ];

          systemd.tmpfiles.rules = [
            "d /var/lib/qbittorrent 0755 ${toString uid} ${toString gid} -"

            "d /arr/torrents 2775 ${toString uid} ${toString mediaGid} -"
            "d /arr/torrents/movies 2775 ${toString uid} ${toString mediaGid} -"
            "d /arr/torrents/tv 2775 ${toString uid} ${toString mediaGid} -"
            "d /arr/torrents/music 2775 ${toString uid} ${toString mediaGid} -"
            "d /arr/torrents/books 2775 ${toString uid} ${toString mediaGid} -"
            "d /arr/torrents/movies/complete 2775 ${toString uid} ${toString mediaGid} -"
            "d /arr/torrents/movies/incomplete 2775 ${toString uid} ${toString mediaGid} -"
            "d /arr/torrents/tv/complete 2775 ${toString uid} ${toString mediaGid} -"
            "d /arr/torrents/tv/incomplete 2775 ${toString uid} ${toString mediaGid} -"
            "d /arr/torrents/music/complete 2775 ${toString uid} ${toString mediaGid} -"
            "d /arr/torrents/music/incomplete 2775 ${toString uid} ${toString mediaGid} -"
            "d /arr/torrents/books/complete 2775 ${toString uid} ${toString mediaGid} -"
            "d /arr/torrents/books/incomplete 2775 ${toString uid} ${toString mediaGid} -"
          ];
        }
      ];
    };

  systemd.services."container@qbittorrent" = {
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "systemd-tmpfiles-setup.service"
    ];
  };
}
