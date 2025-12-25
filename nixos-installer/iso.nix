# Custom NixOS ISO for installation and recovery
# Includes SSH, useful tools, and proper filesystem support
{
  inputs,
  pkgs,
  lib,
  config,
  modulesPath,
  ...
}:
{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
    "${modulesPath}/installer/cd-dvd/channel.nix"
  ];

  # Basic host configuration
  networking.hostName = "nixos-installer";

  nixpkgs = {
    hostPlatform = lib.mkDefault "x86_64-linux";
    config.allowUnfree = true;
  };

  # Enable flakes
  nix = {
    settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
    extraOptions = "experimental-features = nix-command flakes";
  };

  # Configure root user for remote installation
  users.users.root = {
    # Password: "nixos"
    # Generated with: mkpasswd -m sha-512 "nixos"
    hashedPassword = lib.mkForce "$6$RDJI6dFi9AopqKfa$4xY/caVw29yVh6mc7nGaiLmI1rCJE6IVLuCMbnRMtgFoAJoKj9DKX5lfpqwUAEuJqFFtRuOABPfDxrfk6BV.50";
    initialHashedPassword = lib.mkForce null;
    openssh.authorizedKeys.keys = [ ];
  };

  # Enable SSH with root login for installation
  services = {
    openssh = {
      enable = true;
      settings = {
        PermitRootLogin = lib.mkForce "yes";
        PasswordAuthentication = lib.mkForce true;
      };
    };
    qemuGuest.enable = true;
  };

  # Use latest kernel for better hardware support
  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
    supportedFilesystems = lib.mkForce [
      "btrfs"
      "vfat"
      "ext4"
      "xfs"
    ];
  };

  # Auto-start SSH
  systemd = {
    services.sshd.wantedBy = lib.mkForce [ "multi-user.target" ];
    # Disable power management
    targets = {
      sleep.enable = false;
      suspend.enable = false;
      hibernate.enable = false;
      hybrid-sleep.enable = false;
    };
  };

  # Fast compression for quicker ISO builds
  # Level 3 takes <2min vs level 6 which takes >30min
  isoImage.squashfsCompression = "zstd -Xcompression-level 3";

  # Colorful prompt
  programs.bash.promptInit = ''
    export PS1="\\[\\033[01;32m\\]\\u@\\h\\[\\033[00m\\]:\\[\\033[01;34m\\]\\w\\[\\033[00m\\]\\$ "
  '';

  # Enable 256 color support
  environment.variables.TERM = "xterm-256color";

  # Packages for installation
  environment.systemPackages = with pkgs; [
    neovim
    git
    rsync
    # Disk tools
    parted
    gptfdisk
    # Secrets management
    sops
    age
    ssh-to-age
  ];
}
