{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.snapraid-btrfs;
in
{
  options.services.snapraid-btrfs = {
    enable = mkEnableOption "SnapRAID with btrfs snapshot integration";

    contentFiles = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [
        "/mnt/disks/parity0/.snapraid.content"
        "/mnt/snapraid-content/data0/snapraid.content"
      ];
      description = ''
        List of content file locations for SnapRAID.

        For redundancy, it's recommended to store content files on:
        - Each parity disk
        - Each data disk (in a separate subvolume)

        Content files are critical for recovery - if you lose them,
        you cannot recover data from parity!
      '';
    };

    parityFiles = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [
        "/mnt/disks/parity0/snapraid.parity"
        "/mnt/disks/parity1/snapraid.parity"
      ];
      description = ''
        List of parity file locations.
        One parity file per parity disk.
      '';
    };

    dataDisks = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = {
        d0 = "/mnt/disks/data0";
        d1 = "/mnt/disks/data1";
      };
      description = ''
        Attribute set mapping disk names to mount points.
        Disk names should be in the format: d0, d1, d2, etc.
      '';
    };

    exclude = mkOption {
      type = types.listOf types.str;
      default = [
        "*.unrecoverable"
        "/tmp/"
        "/lost+found/"
        "downloads/"
        "appdata/"
        "*.!sync"
        "/.snapshots/"
      ];
      example = [
        "*.unrecoverable"
        "/tmp/"
        "/.snapshots/"
      ];
      description = ''
        List of patterns to exclude from SnapRAID parity.

        Important exclusions:
        - /.snapshots/ - Don't include btrfs snapshots in parity
        - downloads/ - Temporary files you can re-download
        - appdata/ - Application cache that can be regenerated
      '';
    };

    touch = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether to update file access timestamps before sync.
        This helps SnapRAID detect moved/renamed files.
      '';
    };

    scrub = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to enable automatic scrubbing";
      };

      interval = mkOption {
        type = types.str;
        default = "weekly";
        example = "monthly";
        description = ''
          How often to run scrub (systemd timer format).
          Scrubbing verifies parity data integrity.

          Set to empty string to disable automatic scrub.
        '';
      };

      plan = mkOption {
        type = types.int;
        default = 12;
        description = ''
          Scrub plan: percentage of array to scrub each run.
          12% weekly = full array scrubbed every ~8 weeks.
        '';
      };

      olderThan = mkOption {
        type = types.int;
        default = 10;
        description = "Only scrub blocks older than this many days";
      };
    };
  };

  config = mkIf cfg.enable {
    # Install snapraid and snapraid-btrfs packages
    environment.systemPackages = with pkgs; [
      snapraid
      snapraid-btrfs
    ];

    # Configure underlying snapraid service
    services.snapraid = {
      enable = true;
      inherit (cfg)
        contentFiles
        parityFiles
        dataDisks
        exclude
        ;

      # Disable built-in timers (managed by snapraid-btrfs-runner instead)
      sync.interval = "";
      scrub.interval = if cfg.scrub.enable then cfg.scrub.interval else "";

      # Additional snapraid settings
      extraConfig = optionalString cfg.touch ''
        # Update timestamps to help detect moved files
        autosave 500
      '';
    };

    # Assertions for validation
    assertions = [
      {
        assertion = cfg.contentFiles != [ ];
        message = "services.snapraid-btrfs.contentFiles must not be empty. You need at least one content file location.";
      }
      {
        assertion = cfg.parityFiles != [ ];
        message = "services.snapraid-btrfs.parityFiles must not be empty. You need at least one parity file.";
      }
      {
        assertion = cfg.dataDisks != { };
        message = "services.snapraid-btrfs.dataDisks must not be empty. You need at least one data disk.";
      }
      {
        assertion = all (name: hasPrefix "d" name && match "d[0-9]+" name != null) (
          attrNames cfg.dataDisks
        );
        message = "All data disk names must be in format 'd0', 'd1', etc. Invalid names: ${
          toString (
            filter (name: !(hasPrefix "d" name && match "d[0-9]+" name != null)) (attrNames cfg.dataDisks)
          )
        }";
      }
      {
        assertion = length cfg.parityFiles <= 6;
        message = "SnapRAID supports maximum 6 parity files. You have ${toString (length cfg.parityFiles)}.";
      }
      {
        assertion = elem "/.snapshots/" cfg.exclude;
        message = "WARNING: You should exclude /.snapshots/ from parity to avoid duplicating snapshot data!";
      }
    ];

    # Warnings
    warnings =
      optional (length cfg.contentFiles < 2)
        "Only ${toString (length cfg.contentFiles)} content file location configured. For redundancy, configure at least 2 locations (one on parity disk, one on data disk)."
      ++ optional (
        !cfg.touch
      ) "File touch is disabled. SnapRAID may not detect moved/renamed files correctly.";
  };
}
