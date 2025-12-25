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

  # nas1 is behind CGNAT, only update IPv6
  services.cloudflare-dyndns.ipv4 = lib.mkForce false;

  system.stateVersion = config.hostSpec.stateVersion;
}
