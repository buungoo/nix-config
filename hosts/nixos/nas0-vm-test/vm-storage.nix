# Key differences from production:
#	- Uses /dev/vda and /dev/vdb instead of PCIe paths
#	- Smaller partitions (VM has limited disk space)
#	- No containers or complex services
{
  lib,
  pkgs,
  ...
}:
let
  # Import storage helpers
  st = lib.custom.storage;

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

  parityDisks = builtins.filter (d: d.type == "parity") disks;
  dataDisks = builtins.filter (d: d.type == "data") disks;

  snapraidDataDisks = st.mkSnapraidDataDisks dataDisks;
  contentFiles = st.mkSnapraidContentFiles parityDisks dataDisks;
  parityFiles = st.mkSnapraidParityFiles parityDisks;
  snapperConfigs = st.mkSnapperConfigs dataDisks { };
in
{
  disko.devices.disk = {
    vda = {
      type = "disk";
      device = "/dev/vda";
      content = {
        type = "gpt";
        partitions = {
          boot = {
            size = "100M";
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

          root = {
            size = "300M";
            content = st.mkBtrfsPartition "Root" (st.mkSystemSubvolumes { swapSize = "100M"; }) null;
          };

          data0 = {
            size = "100%";
            content =
              st.mkBtrfsPartition "Data0" (st.mkDataDiskSubvolumes "data0")
                "/mnt/snapraid-content/data0";
          };
        };
      };
    };

    vdb = {
      type = "disk";
      device = "/dev/vdb";
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

  environment.systemPackages = with pkgs; [
    mergerfs
    snapper
    btrfs-progs
  ];

  fileSystems."/mnt/storage" = st.mkMergerfsPool dataDisks { minfreespace = "50M"; };

  services.snapraid-btrfs = {
    enable = true;
    inherit contentFiles parityFiles;
    dataDisks = snapraidDataDisks;
    exclude = [
      "*.unrecoverable"
      "/tmp/"
      "/.snapshots/"
    ];
    touch = true;
    scrub.enable = false;
  };

  services.snapper.configs = snapperConfigs;

  services.snapraid-btrfs-runner = {
    enable = false; # Don't auto-run in VM
    snapperConfigs = builtins.map (d: d.name) dataDisks;
    deleteThreshold = 40;
  };

  environment.shellAliases = {
    "sr-sync" = "sudo systemctl start snapraid-btrfs-sync";
    "sr-status" = "sudo snapraid status";
    "snap-list" = "sudo snapper list";
    "btrfs-show" = "sudo btrfs filesystem show";
    "check-mounts" = "df -h | grep -E '(Filesystem|/mnt)'";
  };
}
