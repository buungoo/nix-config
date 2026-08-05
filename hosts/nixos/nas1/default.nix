{
  inputs,
  lib,
  config,
  ...
}:
{
  imports = lib.flatten [
    (map lib.custom.relativeToRoot [
      "hosts/nixos/shared/nas-base.nix"
      "hosts/nixos/shared/hardware-configuration.nix"
      "hosts/nixos/nas1/btrfs-storage.nix"
      "hosts/nixos/nas1/users.nix"
    ])
  ];

  # Host-specific specifications
  hostSpec = {
    hostName = "nas1";
    hostAlias = "Groot";
    stateVersion = "25.11";
    domain = inputs.nix-secrets.nas1.domain;

    # Networking configuration
    networking = {
      externalInterfaces = [
        "enp3s0"
        "enp4s0"
      ];
      localIP = inputs.nix-secrets.nas1.networking.localIP;
      localSubnet = inputs.nix-secrets.nas1.networking.localSubnet;
      localIPv6Subnet = inputs.nix-secrets.nas1.networking.localIPv6Subnet;
      wireguardIP = inputs.nix-secrets.nas1.networking.wireguardIP;
      wireguardIPv4Subnet = inputs.nix-secrets.nas1.networking.wireguardIPv4Subnet;
      wireguardIPv6Subnet = inputs.nix-secrets.nas1.networking.wireguardIPv6Subnet;
    };
  };

  custom.services.cloudflare-dyndns = {
    ipv4 = true;
    ipv6 = true;
  };

  custom.services.qbittorrent.vpn.enable = false;
  custom.services.qbittorrent.vpnFile = inputs.nix-secrets + "/nix/nas1/qbit.nix";
  custom.services.prowlarr.indexerFile = inputs.nix-secrets + "/nix/nas1/prowlarr-indexers.nix";

  custom.services.cross-seed = {
    enable = true;
  }
  // (import (inputs.nix-secrets + "/nix/nas1/cross-seed.nix") {
    inherit config;
    prowlarrNet = lib.custom.mkContainerNetworkConfig config "arr" "prowlarr";
    sonarrNet = lib.custom.mkContainerNetworkConfig config "arr" "sonarr";
    radarrNet = lib.custom.mkContainerNetworkConfig config "arr" "radarr";
  });

  system.stateVersion = config.hostSpec.stateVersion;
}
