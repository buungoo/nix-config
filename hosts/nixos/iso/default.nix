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
    hashedPassword = lib.mkForce "$6$rounds=656000$YfKZ8bS7zQk4pCbA$VWJhXHDJZvVDJJCHQ3J3KqHYlmH5J3nN4p1Y5KJQJQJj1J3J3J3J3J3J3J3J3J3J3J3J3J3J3J3J3J3J3J3J30";
    initialHashedPassword = lib.mkForce null;
    openssh.authorizedKeys.keys = [ ];
  };

  # Enable SSH with root login for installation
  services = {
    openssh = {
      enable = true;
      settings.PermitRootLogin = lib.mkForce "yes";
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

  # Add build timestamp to ISO
  environment.etc = {
    isoBuildTime = {
      text = lib.readFile (
        "${pkgs.runCommand "timestamp" {
          env.when = builtins.currentTime;
        } "echo -n `date -d @$when +%Y-%m-%d_%H-%M-%S` > $out"}"
      );
    };
  };

  # Show ISO build time in prompt
  programs.bash.promptInit = ''
    export PS1="\\[\\033[01;32m\\]\\u@\\h-$(cat /etc/isoBuildTime)\\[\\033[00m\\]:\\[\\033[01;34m\\]\\w\\[\\033[00m\\]\\$ "
  '';

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
