# Complete btrfs storage configuration for nas0
# Combines disk layout (disko) and storage services (snapraid, snapper, mergerfs)
#
# This file manages:
#	1. Physical disk layout and partitioning (disko)
#	2. Btrfs filesystems and subvolumes
#	3. SnapRAID parity protection
#	4. Snapper btrfs snapshots
#	5. Mergerfs unified storage pool
#
# PCIe Slot Mapping (for hot-swap capability):
#	Slot 1 (pci-0000:01:00.0) → nvme0 → System + Data0
#	Slot 2 (pci-0000:02:00.0) → nvme1 → Parity0
#
# To add another data disk:
#	1. Add entry to `disks` list below
#	2. Add disko disk config in disko.devices.disk section
#	3. Everything else (snapraid, snapper, mergerfs) auto-configures!
#
# To swap a drive:
#	1. Shutdown system
#	2. Replace physical drive in PCIe slot
#	3. Boot - disko auto-partitions, formats, creates subvolumes
#	4. Restore data from backup/parity
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Import storage helpers
  st = lib.custom.storage;

  # All disk configurations are derived from this list
  disks = [
    {
      type = "parity";
      name = "parity0";
    }
    {
      type = "data";
      name = "data0";
    }
  ];

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
  disko.devices.disk = {
    # PCIe Slot 1 - System + Data
    nvme0 = {
      type = "disk";
      device = "/dev/disk/by-path/pci-0000:01:00.0-nvme-1";
      content = {
        type = "gpt";
        partitions = {
          # ESP boot partition (1GB)
          boot = {
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [
                "defaults"
                "umask=0077"
              ];
            };
          };

          # Root partition (120GB) - system subvolumes
          root = {
            size = "120G";
            content = st.mkBtrfsPartition "Root" (st.mkSystemSubvolumes { swapSize = "8G"; }) null;
          };

          # Data partition (remaining) - storage subvolumes
          data0 = {
            size = "100%";
            content =
              st.mkBtrfsPartition "Data0" (st.mkDataDiskSubvolumes "data0")
                "/mnt/snapraid-content/data0";
          };
        };
      };
    };

    # PCIe Slot 2 - Parity disk
    nvme1 = {
      type = "disk";
      device = "/dev/disk/by-path/pci-0000:02:00.0-nvme-1";
      content = {
        type = "gpt";
        partitions = {
          parity0 = {
            size = "100%";
            content = st.mkBtrfsPartition "Parity0" {
              "/" = st.mkBtrfsSubvolume "/" "/mnt/disks/parity0" {
                compress = false;
                nocow = true;
              };
            } "/mnt/disks/parity0";
          };
        };
      };
    };
  };

  # Storage Services Configuration

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
}
