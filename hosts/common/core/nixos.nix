# NixOS-specific core configuration
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    inputs.sops-nix.nixosModules.sops
    (lib.custom.relativeToRoot "hosts/common/users/declarative-users.nix")
    (lib.custom.relativeToRoot "hosts/common/core/sops.nix")
  ];

  # Boot loader
  boot.loader.systemd-boot.enable = true;

  # Console and keyboard layout
  console.keyMap = lib.mkDefault "sv-latin1";
  services.xserver.xkb = {
    layout = lib.mkDefault "se";
    variant = lib.mkDefault "nodeadkeys";
  };

  # Locale settings
  i18n = {
    defaultLocale = lib.mkDefault "en_US.UTF-8";
    extraLocaleSettings = lib.mkDefault {
      LC_ADDRESS = lib.mkDefault "sv_SE.UTF-8";
      LC_IDENTIFICATION = lib.mkDefault "sv_SE.UTF-8";
      LC_MEASUREMENT = lib.mkDefault "sv_SE.UTF-8";
      LC_MONETARY = lib.mkDefault "sv_SE.UTF-8";
      LC_NAME = lib.mkDefault "sv_SE.UTF-8";
      LC_NUMERIC = lib.mkDefault "sv_SE.UTF-8";
      LC_PAPER = lib.mkDefault "sv_SE.UTF-8";
      LC_TELEPHONE = lib.mkDefault "sv_SE.UTF-8";
      LC_TIME = lib.mkDefault "sv_SE.UTF-8";
    };
  };

  # Networking
  networking.firewall.enable = true;

  # SSH
  services.openssh.enable = true;

  # Nix settings
  nix.settings.trusted-users = [ "@wheel" ];
  nix.settings.auto-optimise-store = true;

  # Garbage collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-generations +10";
  };
}
