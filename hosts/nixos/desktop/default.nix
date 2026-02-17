{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
{
  imports = lib.flatten [
    (map lib.custom.relativeToRoot [
      "hosts/nixos/desktop/hardware-configuration.nix"
      "hosts/common/core"
      "hosts/nixos/desktop/users.nix"

      # Hardware
      "hosts/nixos/common/optional/nvidia.nix"

      # Optional modules
      "hosts/common/optional/audio.nix"
      "hosts/common/optional/bluetooth.nix"
      "hosts/common/optional/sysc-greet.nix"
      # "hosts/common/optional/tuigreet.nix"
      "hosts/common/optional/opengamepadui.nix"
      "hosts/common/optional/steam.nix"
      "hosts/common/optional/services/wireguard-client.nix"
    ])
  ];

  networking.networkmanager.enable = true;

  environment.systemPackages = [
    inputs.librepods.packages.${pkgs.system}.default # AirPods management
    pkgs.pulsemixer # TUI audio mixer
    pkgs.wiremix
    pkgs.wl-clipboard
    pkgs.kdePackages.dolphin
  ];

  # Enable CUPS to print documents.
  services.printing.enable = true;

  programs = {
    hyprland.enable = true;
    noisetorch.enable = true;
    firefox.enable = true;
    kdeconnect.enable = true;
  };

  hostSpec = {
    hostName = "desktop";
    hostAlias = "Meshy";
    stateVersion = "25.11";
  };

  system.stateVersion = config.hostSpec.stateVersion;
}
