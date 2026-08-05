{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  cfg = config.custom.services.cross-seed;
  net = lib.custom.mkContainerNetworkConfig config cfg.network "cross-seed";

  uid = toString cfg.uid;
  gid = toString cfg.gid;
  mediaGid = 5000;

  sopsFolder = builtins.toString inputs.nix-secrets + "/sops";

  # Helper to resolve container IPs
  qbitNet = lib.custom.mkContainerNetworkConfig config cfg.network "qbittorrent";
  prowlarrNet = lib.custom.mkContainerNetworkConfig config cfg.network "prowlarr";
  sonarrNet = lib.custom.mkContainerNetworkConfig config cfg.network "sonarr";
  radarrNet = lib.custom.mkContainerNetworkConfig config cfg.network "radarr";
in
{
  options.custom.services.cross-seed = {
    enable = lib.mkEnableOption "cross-seed container";

    uid = lib.mkOption {
      type = lib.types.int;
      default = 11000;
      description = "UID for cross-seed user on both host and container";
    };

    gid = lib.mkOption {
      type = lib.types.int;
      default = 11000;
      description = "GID for cross-seed group on both host and container";
    };

    # domain = lib.mkOption {
    #   type = lib.types.str;
    #   default = "cross-seed.${config.hostSpec.domain}";
    #   description = "FQDN for the cross-seed reverse proxy virtual host";
    # };

    network = lib.mkOption {
      type = lib.types.str;
      default = "arr";
      description = "Which containerNetwork to place cross-seed on";
    };

    hostOctet = lib.mkOption {
      type = lib.types.int;
      default = 12;
      description = "Host octet for the container IP in the network subnet.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 2468;
      description = "cross-seed HTTP port";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/cross-seed";
      description = "Host path for persistent cross-seed application data";
    };

    torrentPath = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/storage/arr";
      description = "Host path to the arr root directory (used for torrents and linking)";
    };

    extraSettings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Additional cross-seed settings";
    };

    torznab = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "http://placeholder" ];
      description = "List of Torznab URLs.";
    };

    sonarr = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of Sonarr URLs.";
    };

    radarr = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of Radarr URLs.";
    };
  };

  # Implementation
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.custom.mkContainerServiceConfig "cross-seed" { })
      {
        # Create user on host
        users.users.cross-seed = {
          isSystemUser = true;
          group = "cross-seed";
          extraGroups = [ "media" ];
          uid = cfg.uid;
        };
        users.groups.cross-seed.gid = cfg.gid;

        # Register container network
        hostSpec.networking.containerNetworks.${cfg.network} = {
          bridge = lib.mkDefault "${cfg.network}-bridge";
          subnet = lib.mkDefault "10.0.1.0/24";
          gateway = lib.mkDefault "10.0.1.1";
          containers.cross-seed = lib.mkDefault cfg.hostOctet;
        };

        # Setup bindmount directories
        systemd.tmpfiles.rules = [
          "d ${cfg.dataDir} 0755 ${uid} ${gid} -"
        ];

        # Fetch secrets
        sops.secrets."cross-seed/api-key" = {
          sopsFile = "${sopsFolder}/${config.hostSpec.hostName}.yaml";
          owner = "cross-seed";
          group = "media";
          mode = "0440";
        };

        # Secret settings template for cross-seed
        sops.templates."cross-seed-secrets" = {
          content = builtins.toJSON {
            apiKey = config.sops.placeholder."cross-seed/api-key";
            torrentClients = [
              "qbittorrent:http://bungo:${
                config.sops.placeholder."qbit/plaintext_password"
              }@${qbitNet.containerIP}:${toString config.custom.services.qbittorrent.port}"
            ];
            torznab = cfg.torznab;
            sonarr = cfg.sonarr;
            radarr = cfg.radarr;
          };
          owner = "root";
          group = "root";
          mode = "0400";
        };

        # Container definition
        containers.cross-seed = {
          autoStart = true;
          ephemeral = true;

          bindMounts = {
            "/var/lib/cross-seed" = {
              hostPath = cfg.dataDir;
              isReadOnly = false;
            };
            "/arr" = {
              hostPath = cfg.torrentPath;
              isReadOnly = false;
            };
            "/run/secrets/sonarr/api-key" = {
              hostPath = config.sops.secrets."sonarr/api-key".path;
              isReadOnly = true;
            };
            "/run/secrets/radarr/api-key" = {
              hostPath = config.sops.secrets."radarr/api-key".path;
              isReadOnly = true;
            };
            "/run/secrets/cross-seed-secrets.json" = {

              hostPath = config.sops.templates."cross-seed-secrets".path;
              isReadOnly = true;
            };
          };

          # Network
          privateNetwork = true;
          hostBridge = net.bridge;
          localAddress = "${net.containerIP}/${net.cidr}";

          forwardPorts = [
            {
              hostPort = cfg.port;
              containerPort = cfg.port;
            }
          ];

          config = lib.mkMerge [
            (lib.custom.mkContainerBaseConfig (net // { inherit (config.hostSpec) stateVersion; }))
            {
              # Open firewall for the webhook API
              networking.firewall.allowedTCPPorts = [ cfg.port ];

              environment.variables = {
                CONFIG_DIR = "/var/lib/cross-seed";
                CREDENTIALS_DIRECTORY = "/run/credentials/cross-seed.service";
              };

              services.cross-seed = {
                enable = true;
                settingsFile = "/run/secrets/cross-seed-secrets.json";
                settings = lib.recursiveUpdate {
                  port = cfg.port;
                  useClientTorrents = true; # recommended, uses API
                  delay = 30; # seconds
                  linkCategory = "cross-seed";
                  linkType = "hardlink"; # default
                  linkDirs = [ "/arr/torrents/cross-seed" ];
                  matchMode = "partial"; # allow files that do not fully match
                  fuzzySizeThreshold = 0.02; # default, size deviation in percentage
                  autoResumeMaxDownload = 52428800; # max allowed by cross-seed v6
                  ignoreNonRelevantFilesToResume = false; # default
                  action = "inject";
                  skipRecheck = true;
                  duplicateCategories = true;
                  outputDir = null;

                  # Only necesssary for recovery
                  # dataDirs = [
                  #   "/arr/torrents/movies"
                  #   "/arr/torrents/tv"
                  # ];

                  searchCadence = "1 day"; # how often automatic search runs
                  searchLimit = 400; # max results per run
                  excludeRecentSearch = "3 days";
                  excludeOlder = "9 days";
                } cfg.extraSettings;
              };

              # Container user/group
              users.users.cross-seed = {
                isSystemUser = true;
                uid = lib.mkForce cfg.uid;
                group = "cross-seed";
                extraGroups = [ "media" ];
                home = "/var/lib/cross-seed";
              };
              users.groups.cross-seed.gid = lib.mkForce cfg.gid;
              users.groups.media.gid = mediaGid;
            }
          ];
        };
      }
    ]
  );
}
