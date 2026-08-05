{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  cfg = config.custom.services.qbit-manage;
  qbitNet = lib.custom.mkContainerNetworkConfig config cfg.network "qbittorrent";

  uid = toString cfg.uid;
  gid = toString cfg.gid;
  mediaGid = 5000;

  sopsFolder = builtins.toString inputs.nix-secrets + "/sops";

  defaultSettings = {
    commands = {
      recheck = false;
      cat_update = false;
      tag_update = true;
      rem_unregistered = true;
      tag_tracker_error = true;
      rem_orphaned = true;
      tag_nohardlinks = true;
      share_limits = true;
      cleanup_dirs = true;
      dry_run = false;
    };

    qbt = {
      host = "http://${qbitNet.containerIP}:${toString config.custom.services.qbittorrent.port}";
      user = "bungo";
      pass = config.sops.placeholder."qbit/plaintext_password";
    };

    settings = {
      force_auto_tmm = false;
      tracker_error_tag = "issue";
      nohardlinks_tag = "noHL";
      share_limits_tag = "share_limit";
      share_limits_min_seeding_time_tag = "MinSeedTimeNotReached";
      share_limits_min_num_seeds_tag = "MinSeedsNotMet";
      share_limits_last_active_tag = "LastActiveLimitNotReached";
      # In-progress downloads have no media-library hardlinks yet, so they look
      # like noHL cleanup candidates unless qbit-manage filters them out.
      tag_nohardlinks_filter_completed = true;
      share_limits_filter_completed = true;
    };

    directory = {
      # Use the bind-mount view consistently so rename(2) stays on a single
      # mount point (BindPaths makes /arr alias /mnt/storage/arr inside this
      # unit; using /arr everywhere avoids cross-mount EPERM on cleanup moves).
      # For no-hardlink checks, ignore links inside the torrent tree so
      # original torrent <-> cross-seed links do not mask missing media links.
      root_dir = "${cfg.remotePath}/torrents";
      remote_dir = "${cfg.remotePath}/torrents";
      cross_seed = "${cfg.remotePath}/torrents/cross-seed";
      recycle_bin = "${cfg.remotePath}/.qbit-recycle";
      orphaned_dir = "${cfg.remotePath}/.qbit-orphaned";
      torrents_dir = config.custom.services.qbittorrent.backupPath;
    };

    cat = {
      tv = "${cfg.remotePath}/torrents/tv";
      movies = "${cfg.remotePath}/torrents/movies";
      music = "${cfg.remotePath}/torrents/music";
      books = "${cfg.remotePath}/torrents/books";
      "cross-seed" = "${cfg.remotePath}/torrents/cross-seed";
    };

    tracker = {
      default = {
        tag = "other";
      };
    };

    nohardlinks = {
      tv = {
        exclude_tags = ["cross-seed"];
        ignore_root_dir = true;
      };
      movies = {
        exclude_tags = ["cross-seed"];
        ignore_root_dir = true;
      };
      "cross-seed" = {
        ignore_root_dir = true;
      };
    };

    share_limits = {
      noHL = {
        priority = 1;
        include_all_tags = ["noHL"];
        cleanup = true;
        resume_torrent_after_change = false;
        # qbit-manage stores seed times in minutes. A 24h grace period avoids
        # deleting newly completed torrents before Sonarr has imported them.
        max_ratio = -1;
        max_seeding_time = 1440;
        min_seeding_time = 0;
      };
    };

    recyclebin = {
      # Avoid copying large cleanup candidates into .qbit-recycle. On mergerfs,
      # qbit_manage can fall back from rename to copy, fill the pool, then fail
      # to unlink source files when cross-seed directories are not writable.
      enabled = false;
      empty_after_x_days = 7;
      save_torrents = true;
      split_by_category = false;
    };

    orphaned = {
      # 0 = delete orphans immediately instead of quarantining in orphaned_dir.
      empty_after_x_days = 0;
      max_orphaned_files_to_delete = 250;
      exclude_patterns = [
        "**/.unwanted/*"
        "**/.qbit-recycle/*"
        "**/.qbit-orphaned/*"
      ];
    };
  };
in {
  options.custom.services.qbit-manage = {
    enable = lib.mkEnableOption "qbit-manage scheduled qBittorrent maintenance";

    uid = lib.mkOption {
      type = lib.types.int;
      default = 10800;
      description = "UID for qbit-manage user on host";
    };

    gid = lib.mkOption {
      type = lib.types.int;
      default = 10800;
      description = "GID for qbit-manage group on host";
    };

    network = lib.mkOption {
      type = lib.types.str;
      default = "arr";
      description = "containerNetwork name used to look up the qBittorrent container IP";
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "30min";
      description = "systemd OnUnitActiveSec interval between qbit-manage passes";
    };

    rootPath = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/storage/arr";
      description = "Host filesystem path to the arr root";
    };

    remotePath = lib.mkOption {
      type = lib.types.str;
      default = "/arr";
      description = "Same root as seen from inside the qBittorrent container (its bind mount)";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/qbit-manage";
      description = "Host path for qbit-manage state and logs";
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Extra qbit-manage settings, deep-merged over defaults";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.qbit-manage = {
      isSystemUser = true;
      group = "qbit-manage";
      extraGroups = [
        "media"
        "qbittorrent"
      ];
      uid = cfg.uid;
      home = cfg.dataDir;
      createHome = true;
    };
    users.groups.qbit-manage.gid = cfg.gid;
    users.groups.media.gid = mediaGid;

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 ${uid} ${gid} -"
      "d ${cfg.dataDir}/logs 0750 ${uid} ${gid} -"
      "d ${cfg.rootPath}/.qbit-recycle 2770 ${uid} ${toString mediaGid} -"
      "d ${cfg.rootPath}/.qbit-orphaned 2770 ${uid} ${toString mediaGid} -"
    ];

    sops.templates."qbit-manage-config.yml" = {
      content = builtins.toJSON (lib.recursiveUpdate defaultSettings cfg.settings);
      owner = "qbit-manage";
      group = "qbit-manage";
      mode = "0400";
    };

    systemd.services.qbit-manage = {
      description = "qbit-manage maintenance pass";
      after = [
        "network.target"
        "container@qbittorrent.service"
      ];
      wants = ["container@qbittorrent.service"];
      serviceConfig = {
        Type = "oneshot";
        User = "qbit-manage";
        Group = "qbit-manage";
        SupplementaryGroups = [
          "media"
          "qbittorrent"
        ];
        # qbit-manage reads paths from qBittorrent verbatim (e.g. /arr/torrents/tv/...)
        # and doesn't reliably translate via root_dir/remote_dir in v4.7. Make qbit's
        # view of the FS exist inside this unit's mount namespace so paths work as-is.
        BindPaths = ["${cfg.rootPath}:${cfg.remotePath}"];
        WorkingDirectory = cfg.dataDir;
        # qbit-manage's --config-file flag treats arguments as filenames
        # relative to --config-dir, so absolute sops paths are ignored.
        # Stage the rendered config into the data dir under the default name.
        ExecStartPre = pkgs.writeShellScript "qbit-manage-stage-config" ''
          ${pkgs.coreutils}/bin/install -m 0600 \
            ${config.sops.templates."qbit-manage-config.yml".path} \
            ${cfg.dataDir}/config.yml
        '';
        ExecStart = ''
          ${lib.getExe pkgs.qbit-manage} \
            --run \
            --config-dir ${cfg.dataDir} \
            --log-file ${cfg.dataDir}/logs/qbit-manage.log
        '';
      };
    };

    systemd.timers.qbit-manage = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = cfg.interval;
        Persistent = true;
      };
    };
  };
}
