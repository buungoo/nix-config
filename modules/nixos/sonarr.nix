# You need to look at this:
# https://github.com/xhos/nix/blob/main/modules/nixos/opt/_enrai/services/media/sonarr.nix
# (this one is a bit of a mess)
# https://github.com/upidapi/NixOs/blob/main/modules/nixos/homelab/media/arr.nix
# to even have a chance of configuring this crap
# Also for api endpoints using:
# nix-shell -p jq --run 'curl -s -H "X-Api-Key: $(sudo cat /run/secrets/sonarr/api-key)" http://10.0.1.4:8989/api/v3/<type> | jq ".[].fields[] | {name, value}"'
# where type is e.g. downloadclient

{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  cfg = config.custom.services.sonarr;
  net = lib.custom.mkContainerNetworkConfig config cfg.network "sonarr";

  declarrModule = inputs.declarr.nixosModules.default;

  uid = toString cfg.uid;
  gid = toString cfg.gid;
  mediaGid = 5000;

  sopsFolder = builtins.toString inputs.nix-secrets + "/sops";
in
{
  options.custom.services.sonarr = {
    enable = lib.mkEnableOption "Sonarr container with declarr management";

    uid = lib.mkOption {
      type = lib.types.int;
      default = 10200;
      description = "UID for sonarr user on both host and container";
    };

    gid = lib.mkOption {
      type = lib.types.int;
      default = 10200;
      description = "GID for sonarr group on both host and container";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "sonarr.${config.hostSpec.domain}";
      description = "FQDN for the Sonarr reverse proxy virtual host";
    };

    network = lib.mkOption {
      type = lib.types.str;
      default = "arr";
      description = "Which containerNetwork to place sonarr on";
    };

    hostOctet = lib.mkOption {
      type = lib.types.int;
      default = 4;
      description = "Host octet for the container IP in the network subnet.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8989;
      description = "Sonarr HTTP port";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/sonarr";
      description = "Host path for persistent Sonarr application data";
    };

    rootPath = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/storage/arr";
      description = "Host path to the arr root directory";
    };

    sonarrSettings = lib.mkOption {
      type = lib.types.attrs;
      default = {
      };
      description = "Sonarr application settings";
    };

    declarr = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Declarr configuration for Sonarr";
    };
  };

  # Implementation
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.custom.mkContainerServiceConfig "sonarr" { })
      {
        # Create user on host
        users.users.sonarr = {
          isSystemUser = true;
          group = "sonarr";
          extraGroups = [ "media" ];
          uid = cfg.uid;
        };
        users.groups.sonarr.gid = cfg.gid;

        # Register reverse proxy
        custom.reverseProxy.virtualHosts.sonarr = {
          domain = cfg.domain;
          backendHost = net.containerIP;
          backendPort = cfg.port;
          backendSSL = false;
        };

        # Register container network
        hostSpec.networking.containerNetworks.${cfg.network} = {
          bridge = lib.mkDefault "${cfg.network}-bridge";
          subnet = lib.mkDefault "10.0.1.0/24";
          gateway = lib.mkDefault "10.0.1.1";
          containers.sonarr = lib.mkDefault cfg.hostOctet;
        };

        # Setup bindmount directories
        systemd.tmpfiles.rules = [
          "d ${cfg.dataDir} 0755 ${uid} ${gid} -"
          "d ${cfg.rootPath}/media/tv 0755 ${uid} ${toString mediaGid} -"
        ];

        # Fetch secrets
        sops.secrets."sonarr/api-key" = {
          sopsFile = "${sopsFolder}/${config.hostSpec.hostName}.yaml";
          # Owned by sonarr because declarr does:
          # SONARR__AUTH__APIKEY=$(cat /run/secrets/sonarr/api-key) sonarr -nobrowser -data="/var/lib/sonarr"
          # Really dumb
          # 1. because sonarr has sonarr.environmentFiles to set env variables and
          # 2. forces us to give ownership of the secret to sonarr:media (so other arrs can access)
          owner = "sonarr";
          group = "media";
          mode = "0440";
        };
        sops.secrets."sonarr/password" = {
          sopsFile = "${sopsFolder}/${config.hostSpec.hostName}.yaml";
          owner = "sonarr";
          group = "media";
          mode = "0440";
        };

        # Container definition
        containers.sonarr = {
          autoStart = true;
          ephemeral = true;

          bindMounts = {
            "/var/lib/sonarr" = {
              hostPath = cfg.dataDir;
              isReadOnly = false;
            };
            "/arr" = {
              hostPath = cfg.rootPath;
              isReadOnly = false;
            };
            "/run/secrets/sonarr/api-key" = {
              hostPath = config.sops.secrets."sonarr/api-key".path;
              isReadOnly = true;
            };
            "/run/secrets/sonarr/password" = {
              hostPath = config.sops.secrets."sonarr/password".path;
              isReadOnly = true;
            };
            "/run/secrets/qbit/plaintext_password" = {
              hostPath = config.sops.secrets."qbit/plaintext_password".path;
              isReadOnly = true;
            };
            "/run/secrets/jellarr/api-key" = {
              hostPath = config.sops.secrets."jellarr/api-key".path;
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
              imports = [ declarrModule ];

              services.sonarr = {
                enable = true;
                openFirewall = true;
                dataDir = "/var/lib/sonarr";
                apiKeyFile = "/run/secrets/sonarr/api-key";
                settings = cfg.sonarrSettings;
              };

              # Declarr configures sonarr via API during runtime
              services.declarr = {
                enable = true;
                user = "sonarr";
                group = "sonarr";
                config = {
                  declarr = {
                    stateDir = "/var/lib/sonarr";
                    # Why is this a requirement? Why does it not default??
                    # Anyway pull in dictionarry quality database
                    formatDbRepo = "https://github.com/Dumpstarr/Dumpstarr";
                    formatDbBranch = "stable";
                    customFormatRecreate = true;
                    customFormatPreferRaw = true;
                    globalResolvePaths = [
                      "$.*.config.host.password"
                      "$.*.config.host.passwordConfirmation"
                      "$.*.config.host.apiKey"
                      "$.*.downloadClient.*.fields.password"
                      "$.*.notification.*.fields.apiKey"
                    ];
                  };

                  sonarr = {
                    declarr = {
                      type = "sonarr";
                      url = "http://localhost:${toString cfg.port}";
                    };
                    rootFolder = [ "/arr/media/tv" ];
                    config = {
                      host = {
                        # Specify the API key to declarr
                        # This is dumb btw
                        # 1. because it is under declarr.config.sonarr.config.host what is this naming??
                        # 2. declarr already knows this secret but we have to set it again
                        apiKey = "/run/secrets/sonarr/api-key";

                        authenticationMethod = "forms";
                        authenticationRequired = "disabledForLocalAddresses";
                        username = "bungo";
                        password = config.sops.secrets."sonarr/password".path;
                        # Seriously what is this?
                        # Why not just send the password twice?
                        passwordConfirmation = config.sops.secrets."sonarr/password".path;
                      };
                      # https://dictionarry.dev/media-management/naming
                      naming = {
                        renameEpisodes = true;
                        replaceIllegalCharacters = false; # Not needed on Linux
                        multiEpisodeStyle = 5; # 0 = Extend, 1 = Duplicate, 2 = Repeat, 3 = Scene, 4 = Range, 5 = PrefixedRange
                        # Pulled straight from dictionarry https://github.com/Dictionarry-Hub/database/blob/stable/media_management/naming.yml
                        # Uses MediaInfo which requires MediaManagement.EnableMediaInfo = true
                        standardEpisodeFormat = "{Series TitleYear} - S{season:00}E{episode:00} - {Episode CleanTitle} {[Custom Formats]}{[Quality Full]}{[MediaInfo VideoDynamicRangeType]}{[Mediainfo AudioCodec}{ Mediainfo AudioChannels]}{[MediaInfo VideoCodec]}{-Release Group}";
                        dailyEpisodeFormat = "{Series TitleYear} - {Air-Date} - {Episode CleanTitle} {[Custom Formats]}{[Quality Full]}{[MediaInfo VideoDynamicRangeType]}{[Mediainfo AudioCodec}{ Mediainfo AudioChannels]}{[MediaInfo VideoCodec]}{-Release Group}";
                        animeEpisodeFormat = "{Series TitleYear} - S{season:00}E{episode:00} - {absolute:000} - {Episode CleanTitle} {[Custom Formats]}{[Quality Full]}{[MediaInfo VideoDynamicRangeType]}[{MediaInfo VideoBitDepth}bit]{[MediaInfo VideoCodec]}[{Mediainfo AudioCodec} { Mediainfo AudioChannels}]{MediaInfo AudioLanguages}{-Release Group}";
                        seriesFolderFormat = "{Series TitleYear} {tvdb-{TvdbId}}";
                        seasonFolderFormat = "Season {season:00}";
                      };
                      MediaManagement = {
                        AutoRenameFolders = true;
                        CopyUsingHardlinks = true;
                        EnableMediaInfo = true; # This is the "analyze media files" option
                        RecycleBin = ""; # Delete files immediately
                        SetPermissionsLinux = false;
                      };
                      DownloadClient = {
                        EnableCompletedDownloadHandling = true;
                        RemoveCompletedDownloads = false;
                      };
                    };
                    downloadClient.qBittorrent = {
                      implementation = "QBittorrent";
                      fields = {
                        host = (lib.custom.mkContainerNetworkConfig config cfg.network "qbittorrent").containerIP;
                        port = config.custom.services.qbittorrent.port;
                        username = "bungo";
                        password = config.sops.secrets."qbit/plaintext_password".path;
                        tvCategory = "tv";
                      };
                    };
                    notification.Jellyfin = {
                      implementation = "MediaBrowser";
                      # Other events: onGrab, onDownload, onSeriesAdd, onSeriesDelete, onHealthIssue, onHealthRestored, onApplicationUpdate, onManualInteractionRequired
                      onImportComplete = true;
                      onUpgrade = true;
                      onRename = true;
                      onEpisodeFileDelete = true;
                      onEpisodeFileDeleteForUpgrade = true;
                      fields = {
                        host = (lib.custom.mkContainerNetworkConfig config cfg.network "jellyfin").containerIP;
                        port = config.custom.services.jellyfin.port;
                        apiKey = "/run/secrets/jellarr/api-key";
                        useSsl = false;
                        updateLibrary = true;
                        notify = false;
                        mapFrom = "/arr/media";
                        mapTo = "/media";
                      };
                    };
                    # Why is this a requirement? Should default??
                    qualityProfile = {
                      # https://github.com/Dictionarry-Hub/database/tree/stable/profiles
                      # "2160p Efficient" = { };
                      # "2160p Balanced" = { };
                      "TV 2160p" = {
                        formatScoreOverrides = {
                          AV1 = 1000;
                          "Banned Groups" = -200;
                          "Banned Groups (Title)" = -200;
                          "Scrubs (Banned Groups)" = -200;
                          "Scrubs (Banned Title)" = -200;
                        };
                      };
                      "TV 1080p" = {
                        formatScoreOverrides = {
                          "Banned Groups" = -200;
                          "Banned Groups (Title)" = -200;
                          "Scrubs (Banned Groups)" = -200;
                          "Scrubs (Banned Title)" = -200;
                        };
                      };
                    };
                  };
                };
              };

              # Override declarr systemd deps
              systemd.services.declarr = {
                after = lib.mkForce [
                  "network.target"
                  "sonarr.service"
                ];
                wants = lib.mkForce [ "sonarr.service" ];
                wantedBy = lib.mkForce [ "multi-user.target" ];
                serviceConfig = {
                  Restart = "on-failure";
                  RestartSec = "5s";
                };
              };

              # Container user/group
              # mkForce needed: services.sonarr hardcodes uid 274
              users.users.sonarr = {
                isSystemUser = true;
                uid = lib.mkForce cfg.uid;
                extraGroups = [ "media" ];
              };
              users.groups.sonarr.gid = lib.mkForce cfg.gid;
              users.groups.media.gid = mediaGid;
            }
          ];
        };
      }
    ]
  );
}
