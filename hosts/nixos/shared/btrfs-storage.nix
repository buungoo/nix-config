# Shared btrfs storage services configuration
# Host-specific files (nas0/btrfs-storage.nix, nas1/btrfs-storage.nix) define:
#   1. storage.disks - list of disk configurations
#   2. disko.devices.disk - actual disk layout
#
# This file configures the services based on those disks:
#   - SnapRAID parity protection
#   - Snapper btrfs snapshots
#   - Mergerfs unified storage pool
{
  config,
  lib,
  pkgs,
  ...
}:
let
  st = lib.custom.storage;

  # Read disk configurations from host-specific config
  disks = config.storage.disks;

  # Filter disks by type
  parityDisks = builtins.filter (d: d.type == "parity") disks;
  dataDisks = builtins.filter (d: d.type == "data") disks;

  # Generate derived configurations using helper functions
  snapraidDataDisks = st.mkSnapraidDataDisks dataDisks;
  contentFiles = st.mkSnapraidContentFiles parityDisks dataDisks;
  parityFiles = st.mkSnapraidParityFiles parityDisks;
  snapperConfigs = st.mkSnapperConfigs dataDisks { };
in
{
  # Define option for host-specific configs to set
  options.storage.disks = lib.mkOption {
    type = lib.types.listOf (
      lib.types.submodule {
        options = {
          type = lib.mkOption {
            type = lib.types.enum [
              "parity"
              "data"
            ];
            description = "Type of disk (parity or data)";
          };
          name = lib.mkOption {
            type = lib.types.str;
            description = "Name of the disk (e.g., 'data0', 'parity0')";
          };
        };
      }
    );
    default = [ ];
    description = "List of storage disks for snapraid/snapper/mergerfs configuration";
  };

  config = {
    # Storage packages
    environment.systemPackages = with pkgs; [
      mergerfs
      snapper
      btrfs-progs
    ];

    # Mergerfs - Union filesystem pooling all data disks
    fileSystems."/mnt/storage" = st.mkMergerfsPool dataDisks { minfreespace = "20G"; };

    # SnapRAID with btrfs integration
    services.snapraid-btrfs = {
      enable = true;
      inherit contentFiles parityFiles;
      dataDisks = snapraidDataDisks;

      exclude = [
        "*.unrecoverable"
        "/tmp/"
        "/lost+found/"
        "downloads/" # Temporary downloads
        "appdata/" # Application temp data
        "*.!sync" # Syncthing temp files
        "/.snapshots/" # Don't include snapshots in parity (CRITICAL!)
      ];

      touch = true; # Help detect moved files

      scrub = {
        enable = false; # Disable automatic scrub for now
        interval = "weekly";
        plan = 12;
        olderThan = 10;
      };
    };

    # Snapper - btrfs snapshot management
    services.snapper.configs = snapperConfigs;

    # snapraid-btrfs-runner - Orchestrates sync with snapshots
    services.snapraid-btrfs-runner = {
      enable = true;
      snapperConfigs = builtins.map (d: d.name) dataDisks;
      deleteThreshold = 40;

      timerConfig = {
        OnCalendar = "01:00";
        Persistent = "true";
      };

      performance = {
        nice = 19;
        ioSchedulingPriority = 7;
        cpuSchedulingPolicy = "batch";
      };
    };

    # Helper Commands
    environment.shellAliases = {
      # SnapRAID-btrfs commands
      "sr-sync" = "sudo systemctl start snapraid-btrfs-sync";
      "sr-status" = "sudo snapraid status";
      "sr-diff" = "sudo snapraid diff";
      "sr-smart" = "sudo snapraid smart";
      "sr-scrub" = "sudo snapraid scrub";

      # Snapper commands
      "snap-list" = "sudo snapper list";
      "snap-data0" = "sudo snapper -c data0 list";

      # Btrfs commands
      "btrfs-usage" = "sudo btrfs filesystem usage /mnt/disks/data0";
      "btrfs-df" = "sudo btrfs filesystem df /mnt/disks/data0";
      "btrfs-balance" = "sudo btrfs balance start /mnt/disks/data0";
    };
  };
}
