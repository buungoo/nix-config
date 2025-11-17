{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.snapraid-btrfs-runner;

  runnerPackage = pkgs.snapraid-btrfs-runner.override {
    snapperConfigs = concatStringsSep "," cfg.snapperConfigs;
    deleteThreshold = cfg.deleteThreshold;
  };
in
{
  options.services.snapraid-btrfs-runner = {
    enable = mkEnableOption "snapraid-btrfs-runner service";

    snapperConfigs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [
        "data0"
        "data1"
      ];
      description = ''
        List of snapper configuration names to snapshot before running snapraid sync.
        These must match the snapper configs defined in services.snapper.configs.
      '';
    };

    deleteThreshold = mkOption {
      type = types.int;
      default = 40;
      description = ''
        Abort snapraid sync if more than this many files are deleted.
        Set to -1 to disable this safety check.
      '';
    };

    timerConfig = mkOption {
      type = types.attrsOf types.str;
      default = {
        OnCalendar = "01:00";
        Persistent = "true";
      };
      example = {
        OnCalendar = "daily";
        RandomizedDelaySec = "1h";
      };
      description = ''
        Systemd timer configuration. See systemd.timer(5) for details.
      '';
    };

    performance = {
      nice = mkOption {
        type = types.int;
        default = 19;
        description = "CPU scheduling priority (nice level). 19 is lowest priority.";
      };

      ioSchedulingPriority = mkOption {
        type = types.int;
        default = 7;
        description = "I/O scheduling priority. 7 is lowest priority.";
      };

      cpuSchedulingPolicy = mkOption {
        type = types.str;
        default = "batch";
        description = "CPU scheduling policy. 'batch' is for non-interactive tasks.";
      };
    };
  };

  config = mkIf cfg.enable {
    # Install the runner in systemPackages
    environment.systemPackages = [ runnerPackage ];

    # Systemd service
    systemd.services.snapraid-btrfs-sync = {
      description = "Run snapraid-btrfs sync with runner";

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${runnerPackage}/bin/snapraid-btrfs-runner";

        # Performance tuning
        Nice = cfg.performance.nice;
        IOSchedulingPriority = cfg.performance.ioSchedulingPriority;
        CPUSchedulingPolicy = cfg.performance.cpuSchedulingPolicy;

        # Security hardening
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        RestrictAddressFamilies = "AF_UNIX";
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = "@system-service";
        SystemCallErrorNumber = "EPERM";
        CapabilityBoundingSet = "";
        ProtectSystem = "strict";
        ProtectHome = "read-only";

        # Read-only paths
        ReadOnlyPaths = [
          "/etc/snapraid.conf"
          "/etc/snapper"
        ];

        # Read-write paths will be set by snapraid module
        # We need access to data disks, parity, and content files
        ReadWritePaths =
          let
            snapraidCfg = config.services.snapraid;
          in
          # Data disks
          attrValues snapraidCfg.dataDisks
          # Parity files
          ++ snapraidCfg.parityFiles
          # Content file directories
          ++ map dirOf snapraidCfg.contentFiles;
      };
    };

    # Systemd timer
    systemd.timers.snapraid-btrfs-sync = {
      description = "Timer for snapraid-btrfs sync";
      wantedBy = [ "timers.target" ];

      timerConfig = cfg.timerConfig;
    };

    # Validation: Check that snapper configs exist
    assertions = [
      {
        assertion = cfg.snapperConfigs != [ ] -> config.services.snapper.configs != { };
        message = "services.snapraid-btrfs-runner.snapperConfigs requires services.snapper.configs to be configured";
      }
      {
        assertion = all (name: hasAttr name config.services.snapper.configs) cfg.snapperConfigs;
        message = "All snapraid-btrfs-runner.snapperConfigs must exist in services.snapper.configs. Missing: ${
          toString (filter (name: !hasAttr name config.services.snapper.configs) cfg.snapperConfigs)
        }";
      }
    ];
  };
}
