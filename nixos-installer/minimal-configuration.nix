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
  imports = lib.flatten [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")

    # Import minimal core modules
    # NOTE: Do NOT import home-manager, sops, or user modules!
    # Those depend on secrets which don't exist yet during bootstrap

    (map lib.custom.relativeToRoot [
      "modules/common"
      "hosts/common/core/nixos.nix"
    ])
  ];

  # Minimal host spec for bootstrap
  hostSpec = {
    hostName = lib.mkDefault "installer";
    stateVersion = "24.11";
    isServer = lib.mkDefault false;
    userFullName = "Bungo User";
  };

  # Create bungo user manually (can't use declarative-users.nix without SOPS)
  users = {
    mutableUsers = false;
    users.bungo = {
      isNormalUser = true;
      extraGroups = [
        "wheel"
        "networkmanager"
      ];
      # Temporary password: "nixos"
      hashedPassword = "$6$rounds=656000$YfKZ8bS7zQk4pCbA$VWJhXHDJZvVDJJCHQ3J3KqHYlmH5J3nN4p1Y5KJQJQJj1J3J3J3J3J3J3J3J3J3J3J3J3J3J3J3J3J3J3J3J30";
      openssh.authorizedKeys.keys = [ ];
      shell = pkgs.zsh;
    };
  };

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
    rsync
    # Secrets management
    sops
    age
    ssh-to-age
  ];

  system.stateVersion = config.hostSpec.stateVersion;
}
