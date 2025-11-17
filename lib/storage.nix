{ lib, ... }:
rec {
  # ============================================================================
  # Btrfs Storage Helper Functions
  # ============================================================================
  # Reduces boilerplate in storage configurations by providing reusable
  # builders for common patterns in btrfs + disko + snapraid setups

  # ----------------------------------------------------------------------------
  # mkBtrfsSubvolume - Create a btrfs subvolume mount configuration
  # ----------------------------------------------------------------------------
  # Usage:
  #   mkBtrfsSubvolume "/data" "/mnt/disks/data0" { compress = true; }
  #   mkBtrfsSubvolume "/.snapshots" "/mnt/disks/data0/.snapshots" {}
  #   mkBtrfsSubvolume "/content" "/mnt/snapraid-content/data0" { compress = false; nocow = true; }
  mkBtrfsSubvolume =
    subvolPath: # Subvolume path (e.g., "/data", "/.snapshots")
    mountpoint: # Where to mount (e.g., "/mnt/disks/data0")
    {
      compress ? true, # Enable zstd compression
      nocow ? false, # Disable copy-on-write (for parity/content files)
      ssd ? true, # Enable SSD optimizations
    }:
    {
      inherit mountpoint;
      mountOptions =
        (if compress then [ "compress=zstd" ] else [ "compress=no" ])
        ++ [ "noatime" ]
        ++ (lib.optional ssd "ssd")
        ++ (lib.optional ssd "discard=async")
        ++ (lib.optional nocow "nodatacow")
        ++ (lib.optional nocow "nodatasum");
    };

  # ----------------------------------------------------------------------------
  # mkNocowHook - Generate postCreateHook to set NOCOW attribute
  # ----------------------------------------------------------------------------
  # Usage:
  #   postCreateHook = mkNocowHook "/mnt/disks/parity0";
  mkNocowHook = mountpoint: ''
    MOUNT_POINT="${mountpoint}"
    if mountpoint -q "$MOUNT_POINT"; then
      # Set NOCOW attribute - must be done BEFORE files are created
      chattr +C "$MOUNT_POINT" || echo "Warning: Could not set NOCOW on $MOUNT_POINT"
    fi
  '';

  # ----------------------------------------------------------------------------
  # mkDataDiskSubvolumes - Create standard data disk subvolume structure
  # ----------------------------------------------------------------------------
  # Usage:
  #   mkDataDiskSubvolumes "data0"
  #
  # Creates the standard 4-subvolume structure:
  #   / → /mnt/root/data0 (admin access)
  #   /data → /mnt/disks/data0 (main storage)
  #   /.snapshots → /mnt/disks/data0/.snapshots (snapper)
  #   /content → /mnt/snapraid-content/data0 (snapraid metadata, NOCOW)
  mkDataDiskSubvolumes = diskName: rec {
    # Root of btrfs filesystem (admin access)
    "/" = mkBtrfsSubvolume "/" "/mnt/root/${diskName}" { };

    # Data subvolume (main storage)
    "/data" = mkBtrfsSubvolume "/data" "/mnt/disks/${diskName}" { };

    # Snapshots subvolume (for snapper)
    "/.snapshots" = mkBtrfsSubvolume "/.snapshots" "/mnt/disks/${diskName}/.snapshots" { };

    # Content subvolume (for snapraid metadata - NOCOW!)
    "/content" = mkBtrfsSubvolume "/content" "/mnt/snapraid-content/${diskName}" {
      compress = false;
      nocow = true;
    };
  };

  # ----------------------------------------------------------------------------
  # mkSystemSubvolumes - Create standard system root subvolume structure
  # ----------------------------------------------------------------------------
  # Usage:
  #   mkSystemSubvolumes { swapSize = "8G"; }
  #
  # Creates the standard 4-subvolume structure:
  #   @root → / (ephemeral root)
  #   @nix → /nix (persistent packages)
  #   @persist → /persist (persistent state)
  #   @swap → /swap (swapfile)
  mkSystemSubvolumes =
    {
      swapSize ? "8G",
    }:
    rec {
      "@root" = mkBtrfsSubvolume "@root" "/" { };
      "@nix" = mkBtrfsSubvolume "@nix" "/nix" { };
      "@persist" = mkBtrfsSubvolume "@persist" "/persist" { };
      "@swap" = {
        mountpoint = "/swap";
        swap.swapfile.size = swapSize;
      };
    };

  # ----------------------------------------------------------------------------
  # mkBtrfsPartition - Create a btrfs partition with subvolumes
  # ----------------------------------------------------------------------------
  # Usage:
  #   mkBtrfsPartition "Data0" {
  #     "/" = mkSub ...;
  #     "/data" = mkSub ...;
  #   } "/mnt/snapraid-content/data0"
  mkBtrfsPartition =
    label: # Filesystem label
    subvolumes: # Attribute set of subvolumes
    nocowPath: # Optional path to set NOCOW (null to disable)
    {
      type = "btrfs";
      extraArgs = [
        "-f"
        "-L"
        label
      ];
      inherit subvolumes;
    }
    // (lib.optionalAttrs (nocowPath != null) {
      postCreateHook = mkNocowHook nocowPath;
    });

  # ----------------------------------------------------------------------------
  # mkSnapraidDataDisks - Generate snapraid data disk mapping
  # ----------------------------------------------------------------------------
  # Usage:
  #   mkSnapraidDataDisks [ { name = "data0"; ... } { name = "data1"; ... } ]
  #
  # Output: { d0 = "/mnt/disks/data0"; d1 = "/mnt/disks/data1"; }
  mkSnapraidDataDisks =
    dataDisks:
    builtins.listToAttrs (
      lib.lists.imap0 (i: d: {
        name = "d${toString i}";
        value = "/mnt/disks/${d.name}";
      }) dataDisks
    );

  # ----------------------------------------------------------------------------
  # mkSnapraidContentFiles - Generate snapraid content file locations
  # ----------------------------------------------------------------------------
  # Usage:
  #   mkSnapraidContentFiles parityDisks dataDisks
  #
  # Creates redundant content files:
  #   - One on each parity disk root
  #   - One on each data disk's content subvolume
  mkSnapraidContentFiles =
    parityDisks: dataDisks:
    (builtins.map (p: "/mnt/disks/${p.name}/.snapraid.content") parityDisks)
    ++ builtins.map (d: "/mnt/snapraid-content/${d.name}/snapraid.content") dataDisks;

  # ----------------------------------------------------------------------------
  # mkSnapraidParityFiles - Generate snapraid parity file locations
  # ----------------------------------------------------------------------------
  # Usage:
  #   mkSnapraidParityFiles parityDisks
  #
  # Output: [ "/mnt/disks/parity0/snapraid.parity" ... ]
  mkSnapraidParityFiles =
    parityDisks: builtins.map (p: "/mnt/disks/${p.name}/snapraid.parity") parityDisks;

  # ----------------------------------------------------------------------------
  # mkSnapperConfigs - Generate snapper configs for data disks
  # ----------------------------------------------------------------------------
  # Usage:
  #   mkSnapperConfigs dataDisks { numberLimit = 20; }
  #
  # Creates snapper configuration for each data disk with sensible defaults
  mkSnapperConfigs =
    dataDisks:
    {
      timelineCreate ? false, # Disable automatic timeline snapshots
      numberLimit ? "10", # Total snapshot limit
      numberLimitImportant ? "5", # Important snapshot limit
      allowGroups ? [ "wheel" ], # Groups allowed to view snapshots
      syncAcl ? true, # Sync ACLs between snapshots
    }:
    builtins.listToAttrs (
      builtins.map (d: {
        name = "${d.name}";
        value = {
          SUBVOLUME = "/mnt/disks/${d.name}";
          TIMELINE_CREATE = timelineCreate;
          NUMBER_LIMIT = numberLimit;
          NUMBER_LIMIT_IMPORTANT = numberLimitImportant;
          ALLOW_GROUPS = allowGroups;
          SYNC_ACL = syncAcl;
        };
      }) dataDisks
    );

  # ----------------------------------------------------------------------------
  # mkMergerfsPool - Create mergerfs union filesystem configuration
  # ----------------------------------------------------------------------------
  # Usage:
  #   mkMergerfsPool dataDisks { minfreespace = "50G"; }
  mkMergerfsPool =
    dataDisks:
    {
      minfreespace ? "20G", # Reserve space per disk
      createPolicy ? "mfs", # Most free space
      cacheFiles ? "off", # Disable file caching for NAS reliability
    }:
    {
      device = lib.strings.concatMapStringsSep ":" (d: "/mnt/disks/${d.name}") dataDisks;
      fsType = "fuse.mergerfs";
      options = [
        "defaults"
        "nofail"
        "allow_other"
        "use_ino" # Critical for hardlinks!
        "cache.files=${cacheFiles}"
        "dropcacheonclose=true"
        "category.create=${createPolicy}"
        "moveonenospc=true"
        "minfreespace=${minfreespace}"
        "fsname=mergerfs"
      ];
    };
}
