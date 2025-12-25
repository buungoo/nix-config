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
      "hosts/nixos/nas0/btrfs-storage.nix"
      "hosts/nixos/nas0/users.nix"
    ])
  ];

  # Host-specific specifications
  hostSpec = {
    hostName = "nas0";
    hostAlias = "Grogu";
    stateVersion = "25.05";
    domain = inputs.nix-secrets.nas0.domain;

    # Networking configuration
    networking = {
      externalInterfaces = [
        "enp3s0"
        "enp4s0"
      ];
      localIP = inputs.nix-secrets.nas0.networking.localIP;
      localSubnet = inputs.nix-secrets.nas0.networking.localSubnet;
      localIPv6Subnet = inputs.nix-secrets.nas0.networking.localIPv6Subnet;
      wireguardIP = inputs.nix-secrets.nas0.networking.wireguardIP;
      wireguardIPv4Subnet = inputs.nix-secrets.nas0.networking.wireguardIPv4Subnet;
      wireguardIPv6Subnet = inputs.nix-secrets.nas0.networking.wireguardIPv6Subnet;
    };
  };

  system.stateVersion = config.hostSpec.stateVersion;

  # set the CPU scaling governor system-wide - Commented this out because I think the machine handles this automatically? The BIOS suggests so
  # Check p-state policy: cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor
  # check c-state policy: cat /sys/devices/system/cpu/cpuidle/current_driver
  # powerManagement.enable = true;
  # powerManagement.cpuFreqGovernor = "performance";
}
