{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  cfg = config.custom.services.jellyseerr;
  net = lib.custom.mkContainerNetworkConfig config cfg.network "seerr";

  declarrModule = inputs.declarr.nixosModules.default;

  uid = toString cfg.uid;
  gid = toString cfg.gid;

  sopsFolder = builtins.toString inputs.nix-secrets + "/sops";

  jellyfinNet = lib.custom.mkContainerNetworkConfig config cfg.network "jellyfin";
  sonarrNet = lib.custom.mkContainerNetworkConfig config cfg.network "sonarr";
  radarrNet = lib.custom.mkContainerNetworkConfig config cfg.network "radarr";
in
{
  options.custom.services.jellyseerr = {
    enable = lib.mkEnableOption "Jellyseerr container with declarr management";

    uid = lib.mkOption {
      type = lib.types.int;
      default = 10600;
      description = "UID for jellyseerr user on both host and container";
    };

    gid = lib.mkOption {
      type = lib.types.int;
      default = 10600;
      description = "GID for jellyseerr group on both host and container";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "seerr.${config.hostSpec.domain}";
      description = "FQDN for the Jellyseerr reverse proxy virtual host";
    };

    network = lib.mkOption {
      type = lib.types.str;
      default = "arr";
      description = "Which containerNetwork to place jellyseerr on";
    };

    hostOctet = lib.mkOption {
      type = lib.types.int;
      default = 3;
      description = "Host octet for the container IP in the network subnet.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 5055;
      description = "Jellyseerr HTTP port";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/seerr";
      description = "Host path for persistent Jellyseerr application data";
    };
  };

  # Implementation
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.custom.mkContainerServiceConfig "jellyseerr" { })
      {
        # Create user on host
        users.users.seerr = {
          isSystemUser = true;
          group = "seerr";
          uid = cfg.uid;
        };
        users.groups.seerr.gid = cfg.gid;

        # Register reverse proxy
        custom.reverseProxy.virtualHosts.jellyseerr = {
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
          containers.seerr = lib.mkDefault cfg.hostOctet;
        };

        # Setup bindmount directories
        systemd.tmpfiles.rules = [
          "d ${cfg.dataDir} 0755 ${uid} ${gid} -"
        ];

        # Fetch secrets
        # Jellyseerr's own API key only, sonarr/radarr/jellarr secrets are readable via media group
        sops.secrets."seerr/api-key" = {
          sopsFile = "${sopsFolder}/${config.hostSpec.hostName}.yaml";
          owner = "seerr";
          group = "seerr";
          mode = "0400";
        };

        # Container definition
        containers.jellyseerr = {
          autoStart = true;
          ephemeral = true;

          bindMounts = {
            "/var/lib/seerr" = {
              hostPath = cfg.dataDir;
              isReadOnly = false;
            };
            "/run/secrets/seerr/api-key" = {
              hostPath = config.sops.secrets."seerr/api-key".path;
              isReadOnly = true;
            };
            "/run/secrets/jellarr/api-key" = {
              hostPath = config.sops.secrets."jellarr/api-key".path;
              isReadOnly = true;
            };
            "/run/secrets/jellarr/passwords/bungo" = {
              hostPath = config.sops.secrets."jellarr/passwords/bungo".path;
              isReadOnly = true;
            };
            "/run/secrets/sonarr/api-key" = {
              hostPath = config.sops.secrets."sonarr/api-key".path;
              isReadOnly = true;
            };
            "/run/secrets/radarr/api-key" = {
              hostPath = config.sops.secrets."radarr/api-key".path;
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

              # Jellyseerr runs under declarr's control (declarr --sync --run jellyseerr)
              # The declarr module overrides ExecStart automatically
              services.jellyseerr = {
                enable = true;
                openFirewall = true;
                port = cfg.port;
                configDir = "/var/lib/seerr";

                config = {
                  declarr = {
                    resolvePaths = [
                      "$.main.apiKey"
                      "$.jellyfin.apiKey"
                      "$.jellyfin.password"
                      "$.radarr[*].apiKey"
                      "$.sonarr[*].apiKey"
                    ];
                    url = "http://localhost:${toString cfg.port}";
                  };

                  jellyfin = {
                    name = config.hostSpec.hostName;
                    apiKey = "/run/secrets/jellarr/api-key";
                    username = "bungo";
                    email = "";
                    password = "/run/secrets/jellarr/passwords/bungo";
                    ip = jellyfinNet.containerIP;
                    port = config.custom.services.jellyfin.port;
                    useSsl = false;
                    urlBase = "";
                    externalHostname = "https://${config.custom.services.jellyfin.domain}";
                    libraries = [
                      {
                        enabled = true;
                        name = "Movies";
                        type = "movie";
                      }
                      {
                        enabled = true;
                        name = "Series";
                        type = "show";
                      }
                    ];
                  };

                  main = {
                    apiKey = "/run/secrets/seerr/api-key";
                    defaultPermissions = {
                      request = true;
                      request4k = true;
                      autoApprove = true;
                      autoApprove4k = true;
                      autoRequest = true;
                    };
                    applicationTitle = "Jellyseerr";
                    applicationUrl = "https://${cfg.domain}";
                    localLogin = true;
                    mediaServerLogin = true;
                    mediaServerType = 2;
                    region = "SE";
                    originalLanguage = "";
                  };

                  public = {
                    initialized = true;
                  };

                  radarr = [
                    {
                      id = 0;
                      name = "radarr";
                      apiKey = "/run/secrets/radarr/api-key";
                      hostname = radarrNet.containerIP;
                      port = config.custom.services.radarr.port;
                      externalUrl = "https://${config.custom.services.radarr.domain}";
                      useSsl = false;
                      is4k = false;
                      isDefault = true;
                      syncEnabled = true;
                      preventSearch = false;
                      minimumAvailability = "released";
                      tags = [ ];
                      tagRequests = false;
                      activeDirectory = "/arr/media/movies";
                      activeProfileName = "Movies 2160p"; #"2160p Efficient";
                    }
                  ];

                  sonarr = [
                    {
                      id = 0;
                      name = "sonarr";
                      apiKey = "/run/secrets/sonarr/api-key";
                      hostname = sonarrNet.containerIP;
                      port = config.custom.services.sonarr.port;
                      externalUrl = "https://${config.custom.services.sonarr.domain}";
                      useSsl = false;
                      is4k = false;
                      isDefault = true;
                      syncEnabled = true;
                      preventSearch = false;
                      enableSeasonFolders = true;
                      tags = [ ];
                      animeTags = [ ];
                      tagRequests = false;
                      activeDirectory = "/arr/media/tv";
                      activeProfileName = "TV 2160p"; #"2160p Efficient";
                    }
                  ];

                  tautulli = { };
                };
              };

              # Override jellyseerr systemd service for container environment
              systemd.services.jellyseerr = {
                after = lib.mkForce [ "network.target" ];
                wants = lib.mkForce [ ];
                serviceConfig = {
                  DynamicUser = lib.mkForce false;
                  User = "seerr";
                  Group = "seerr";
                  StateDirectory = lib.mkForce "seerr";
                };
              };

              # Container user/group
              users.users.seerr = {
                isSystemUser = true;
                group = "seerr";
                uid = lib.mkForce cfg.uid;
                extraGroups = [ "media" ];
              };
              users.groups.seerr.gid = lib.mkForce cfg.gid;
              users.groups.media.gid = 5000;
            }
          ];
        };
      }
    ]
  );
}
