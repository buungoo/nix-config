# Minimal NixOS configuration for bootstrapping new systems
# This imports core modules from the main yano config
{
  inputs,
  outputs,
  lib,
  pkgs,
  config,
  modulesPath,
  ...
}:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")

    # Import service modules so options exist (services won't run until full rebuild)
    (lib.custom.relativeToRoot "modules/services/snapraid-btrfs.nix")
    (lib.custom.relativeToRoot "modules/services/snapraid-btrfs-runner.nix")
  ];

  # Mutable users for bootstrap - will be replaced by full config
  users.mutableUsers = true;

  # Temporary root password for local console access
  # Password: "nixos"
  # Generated with: mkpasswd -m sha-512 "nixos"
  users.users.root.hashedPassword = "$6$RDJI6dFi9AopqKfa$4xY/caVw29yVh6mc7nGaiLmI1rCJE6IVLuCMbnRMtgFoAJoKj9DKX5lfpqwUAEuJqFFtRuOABPfDxrfk6BV.50";

  # Boot configuration
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    kernelPackages = pkgs.linuxPackages_latest;
  };

  # Basic networking
  networking = {
    networkmanager.enable = true;
    useDHCP = lib.mkDefault true;
  };

  # Enable SSH for remote access
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  # Time zone
  time.timeZone = "Europe/Stockholm";

  # Locale
  i18n.defaultLocale = "sv_SE.UTF-8";

  # Allow sudo without password (temporary for bootstrap)
  security.sudo.wheelNeedsPassword = false;

  # Additional packages needed for bootstrap
  environment.systemPackages = with pkgs; [
    git
    rsync
  ];

  system.stateVersion = "25.11";
}
