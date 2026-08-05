# Almost identical to sonarr.nix
# See sonarr.nix for additional comments
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  cfg = config.custom.services.radarr;
  net = lib.custom.mkContainerNetworkConfig config cfg.network "radarr";

  declarrModule = inputs.declarr.nixosModules.default;

  uid = toString cfg.uid;
  gid = toString cfg.gid;
  mediaGid = 5000;

  sopsFolder = builtins.toString inputs.nix-secrets + "/sops";
in
{
  options.custom.services.radarr = {
    enable = lib.mkEnableOption "Radarr container with declarr management";

    uid = lib.mkOption {
      type = lib.types.int;
      default = 10300;
      description = "UID for radarr user on both host and container";
    };

    gid = lib.mkOption {
      type = lib.types.int;
      default = 10300;
      description = "GID for radarr group on both host and container";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "radarr.${config.hostSpec.domain}";
      description = "FQDN for the Radarr reverse proxy virtual host";
    };

    network = lib.mkOption {
      type = lib.types.str;
      default = "arr";
      description = "Which containerNetwork to place radarr on";
    };

    hostOctet = lib.mkOption {
      type = lib.types.int;
      default = 5;
      description = "Host octet for the container IP in the network subnet.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 7878;
      description = "Radarr HTTP port";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/radarr";
      description = "Host path for persistent Radarr application data";
    };

    rootPath = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/storage/arr";
      description = "Host path to the arr root directory";
    };

    radarrSettings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Radarr application settings";
    };
  };

  # Implementation
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.custom.mkContainerServiceConfig "radarr" { })
      {
        # Create user on host
        users.users.radarr = {
          isSystemUser = true;
          group = "radarr";
          extraGroups = [ "media" ];
          uid = cfg.uid;
        };
        users.groups.radarr.gid = cfg.gid;

        # Register reverse proxy
        custom.reverseProxy.virtualHosts.radarr = {
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
          containers.radarr = lib.mkDefault cfg.hostOctet;
        };

        # Setup bindmount directories
        systemd.tmpfiles.rules = [
          "d ${cfg.dataDir} 0755 ${uid} ${gid} -"
          "d ${cfg.rootPath}/media/movies 2775 ${uid} ${toString mediaGid} -"
        ];

        # Fetch secrets
        sops.secrets."radarr/api-key" = {
          sopsFile = "${sopsFolder}/${config.hostSpec.hostName}.yaml";
          owner = "radarr";
          group = "media";
          mode = "0440";
        };
        sops.secrets."radarr/password" = {
          sopsFile = "${sopsFolder}/${config.hostSpec.hostName}.yaml";
          owner = "radarr";
          group = "media";
          mode = "0440";
        };

        # Container definition
        containers.radarr = {
          autoStart = true;
          ephemeral = true;

          bindMounts = {
            "/var/lib/radarr" = {
              hostPath = cfg.dataDir;
              isReadOnly = false;
            };
            "/arr" = {
              hostPath = cfg.rootPath;
              isReadOnly = false;
            };
            "/run/secrets/radarr/api-key" = {
              hostPath = config.sops.secrets."radarr/api-key".path;
              isReadOnly = true;
            };
            "/run/secrets/radarr/password" = {
              hostPath = config.sops.secrets."radarr/password".path;
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

              services.radarr = {
                enable = true;
                openFirewall = true;
                dataDir = "/var/lib/radarr";
                apiKeyFile = "/run/secrets/radarr/api-key";
                settings = cfg.radarrSettings;
              };

              # Declarr configures radarr via API during runtime
              services.declarr = {
                enable = true;
                user = "radarr";
                group = "radarr";

                formatDb = inputs.dumpstarr;

                config = {
                  declarr = {
                    stateDir = "/var/lib/radarr";
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

                  radarr = {
                    declarr = {
                      type = "radarr";
                      url = "http://localhost:${toString cfg.port}";
                    };
                    rootFolder = [ "/arr/media/movies" ];
                    config = {
                      host = {
                        apiKey = "/run/secrets/radarr/api-key";
                        authenticationMethod = "forms";
                        authenticationRequired = "disabledForLocalAddresses";
                        username = "bungo";
                        password = config.sops.secrets."radarr/password".path;
                        passwordConfirmation = config.sops.secrets."radarr/password".path;
                      };
                      naming = {
                        renameMovies = true;
                        replaceIllegalCharacters = false;
                        standardMovieFormat = "{Movie CleanTitle} {(Release Year)} {tmdb-{TmdbId}} {edition-{Edition Tags}} {[Custom Formats]}{[Quality Full]}{[MediaInfo 3D]}{[MediaInfo VideoDynamicRangeType]}{[Mediainfo AudioCodec}{ Mediainfo AudioChannels]}{[Mediainfo VideoCodec]}{-Release Group}";
                        movieFolderFormat = "{Movie CleanTitle} ({Release Year}) {tmdb-{TmdbId}}";
                      };
                      MediaManagement = {
                        AutoRenameFolders = true;
                        CopyUsingHardlinks = true;
                        EnableMediaInfo = true;
                        RecycleBin = "";
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
                        movieCategory = "movies";
                      };
                    };
                    notification.Jellyfin = {
                      implementation = "MediaBrowser";
                      onImportComplete = true;
                      onUpgrade = true;
                      onRename = true;
                      onMovieFileDelete = true;
                      onMovieFileDeleteForUpgrade = true;
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
                    qualityProfile = {
                      # "2160p Efficient" = { };
                      # "2160p Balanced" = { };
                      "Movies 2160p" = {
                        formatScoreOverrides = {
                          AV1 = 1000;
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

              # UMask 0002 so created movie dirs are 2775 (group-writable),
              # which lets bazarr (member of `media`) write .srt files alongside.
              systemd.services.radarr.serviceConfig.UMask = lib.mkForce "0002";

              # Override declarr systemd deps
              systemd.services.declarr = {
                after = lib.mkForce [
                  "network.target"
                  "radarr.service"
                ];
                wants = lib.mkForce [ "radarr.service" ];
                wantedBy = lib.mkForce [ "multi-user.target" ];
                serviceConfig = {
                  Restart = "on-failure";
                  RestartSec = "5s";
                };
              };

              # Container user/group
              # mkForce needed: services.radarr hardcodes uid 275
              users.users.radarr = {
                isSystemUser = true;
                uid = lib.mkForce cfg.uid;
                extraGroups = [ "media" ];
              };
              users.groups.radarr.gid = lib.mkForce cfg.gid;
              users.groups.media.gid = mediaGid;
            }
          ];
        };
      }
    ]
  );
}
