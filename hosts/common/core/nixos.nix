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
    (lib.custom.relativeToRoot "modules/nixos")
    (lib.custom.relativeToRoot "hosts/common/users/declarative-users.nix")
    (lib.custom.relativeToRoot "hosts/common/core/sops-nixos.nix")
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
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  # Nix settings
  nix.settings.trusted-users = [ "@wheel" ];
  nix.settings.auto-optimise-store = true;

  programs.nh = {
    enable = true;
    clean.enable = true;
    clean.extraArgs = "--keep-since 7d --keep 5";
    flake = "/home/bungo/.nixos/nix-config";
  };
}
