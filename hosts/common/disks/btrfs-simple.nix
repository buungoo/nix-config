# Simple btrfs disk configuration for generic installs
# Parameters:
#   disk - device path (e.g., "/dev/sda", "/dev/nvme0n1")
#   withSwap - whether to create a swap subvolume
#   swapSize - size of swap in GiB (only used if withSwap is true)
{
  disk,
  withSwap ? false,
  swapSize ? "8",
  ...
}:
{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = disk;
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

            # Root partition with btrfs subvolumes
            root = {
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = [
                  "-f"
                  "-L"
                  "nixos"
                ];
                subvolumes = {
                  # Root subvolume
                  "@root" = {
                    mountpoint = "/";
                    mountOptions = [
                      "compress=zstd"
                      "noatime"
                    ];
                  };

                  # Nix store subvolume
                  "@nix" = {
                    mountpoint = "/nix";
                    mountOptions = [
                      "compress=zstd"
                      "noatime"
                    ];
                  };
                }
                // (
                  if withSwap then
                    {
                      # Swap subvolume
                      "@swap" = {
                        mountpoint = "/swap";
                        swap.swapfile.size = "${swapSize}G";
                      };
                    }
                  else
                    { }
                );
              };
            };
          };
        };
      };
    };
  };
}
