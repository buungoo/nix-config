{
  inputs,
  lib,
  pkgs,
  outputs,
  ...
}:
{
  nixpkgs.hostPlatform = "x86_64-linux";

  imports = [
    inputs.disko.nixosModules.disko

    (lib.custom.relativeToRoot "modules/services/snapraid-btrfs.nix")
    (lib.custom.relativeToRoot "modules/services/snapraid-btrfs-runner.nix")

    ./vm-storage.nix
  ];
  system.stateVersion = "25.05";

  nixpkgs.overlays = [
    outputs.overlays.default
  ];

  environment.systemPackages = with pkgs; [
    vim
    git
    btrfs-progs
    mergerfs
    snapraid
  ];

  services.openssh.enable = true;

  services.getty.autologinUser = "root";

  virtualisation.vmVariant = {
    virtualisation = {
      memorySize = 2048;
      cores = 2;

      emptyDiskImages = [
        1024 # 1GB disk for nvme0 (system + data)
        512 # 512MB disk for nvme1 (parity)
      ];

      graphics = false;
      qemu.options = [ "-nographic" ];
    };
  };

  networking = {
    hostName = "nas0-vm-test";
    useDHCP = false;
    interfaces.eth0.useDHCP = true;
  };

  users.users.testuser = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    password = "test";
  };
}
