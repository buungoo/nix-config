# nas1-specific btrfs storage configuration
# Defines the physical disks and their layout for nas1
#
# PCIe Slot Mapping (for hot-swap capability):
#	Slot 1 (pci-0000:01:00.0) → nvme0 → System + Data0
#	Slot 2 (pci-0000:02:00.0) → nvme1 → Parity0
#
# To add another data disk in the future:
#	1. Add entry to storage.disks list below
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
  st = lib.custom.storage;
in
{
  imports = [ ../shared/btrfs-storage.nix ];
  # Define disk list for shared services (snapraid, snapper, mergerfs)
  storage.disks = [
    {
      type = "parity";
      name = "parity0";
    }
    {
      type = "data";
      name = "data0";
    }
    # Future: Add data1 here when adding another NVMe
    # {
    #   type = "data";
    #   name = "data1";
    # }
  ];

  # Physical disk layout
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

    # Future: Add nvme2 here when adding another NVMe
    # nvme2 = {
    #   type = "disk";
    #   device = "/dev/disk/by-path/pci-0000:03:00.0-nvme-1";
    #   content = {
    #     type = "gpt";
    #     partitions = {
    #       data1 = {
    #         size = "100%";
    #         content =
    #           st.mkBtrfsPartition "Data1" (st.mkDataDiskSubvolumes "data1")
    #             "/mnt/snapraid-content/data1";
    #       };
    #     };
    #   };
    # };
  };
}
