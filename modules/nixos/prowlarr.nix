{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  cfg = config.custom.services.prowlarr;
  net = lib.custom.mkContainerNetworkConfig config cfg.network "prowlarr";

  declarrModule = inputs.declarr.nixosModules.default;

  uid = toString cfg.uid;
  gid = toString cfg.gid;

  sopsFolder = builtins.toString inputs.nix-secrets + "/sops";
  indexers = import (inputs.nix-secrets + "/nix/prowlarr-indexers.nix");
in
{
  options.custom.services.prowlarr = {
    enable = lib.mkEnableOption "Prowlarr container with declarr management";

    uid = lib.mkOption {
      type = lib.types.int;
      default = 10700;
      description = "UID for prowlarr user on both host and container";
    };

    gid = lib.mkOption {
      type = lib.types.int;
      default = 10700;
      description = "GID for prowlarr group on both host and container";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "prowlarr.${config.hostSpec.domain}";
      description = "FQDN for the Prowlarr reverse proxy virtual host";
    };

    network = lib.mkOption {
      type = lib.types.str;
      default = "arr";
      description = "Which containerNetwork to place prowlarr on";
    };

    hostOctet = lib.mkOption {
      type = lib.types.int;
      default = 6;
      description = "Host octet for the container IP in the network subnet.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 9696;
      description = "Prowlarr HTTP port";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/prowlarr";
      description = "Host path for persistent Prowlarr application data";
    };
  };

  # Implementation
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.custom.mkContainerServiceConfig "prowlarr" { })
      {
        # Create user on host
        users.users.prowlarr = {
          isSystemUser = true;
          group = "prowlarr";
          uid = cfg.uid;
        };
        users.groups.prowlarr.gid = cfg.gid;

        # Register reverse proxy
        custom.reverseProxy.virtualHosts.prowlarr = {
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
          containers.prowlarr = lib.mkDefault cfg.hostOctet;
        };

        # Setup bindmount directories
        systemd.tmpfiles.rules = [
          "d ${cfg.dataDir} 0755 ${uid} ${gid} -"
        ];

        # Fetch secrets
        sops.secrets."prowlarr/api-key" = {
          sopsFile = "${sopsFolder}/${config.hostSpec.hostName}.yaml";
          owner = "prowlarr";
          group = "media";
          mode = "0440";
        };
        sops.secrets."prowlarr/password" = {
          sopsFile = "${sopsFolder}/${config.hostSpec.hostName}.yaml";
          owner = "prowlarr";
          group = "prowlarr";
          mode = "0400";
        };
        sops.secrets."prowlarr/indexer-a/api-key" = {
          sopsFile = "${sopsFolder}/${config.hostSpec.hostName}.yaml";
          owner = "prowlarr";
          group = "prowlarr";
          mode = "0400";
        };
        sops.secrets."prowlarr/indexer-b/api-key" = {
          sopsFile = "${sopsFolder}/${config.hostSpec.hostName}.yaml";
          owner = "prowlarr";
          group = "prowlarr";
          mode = "0400";
        };
        sops.secrets."prowlarr/indexer-b/rss-key" = {
          sopsFile = "${sopsFolder}/${config.hostSpec.hostName}.yaml";
          owner = "prowlarr";
          group = "prowlarr";
          mode = "0400";
        };
        sops.secrets."prowlarr/indexer-c/api-key" = {
          sopsFile = "${sopsFolder}/${config.hostSpec.hostName}.yaml";
          owner = "prowlarr";
          group = "prowlarr";
          mode = "0400";
        };
        sops.secrets."prowlarr/indexer-d/api-key" = {
          sopsFile = "${sopsFolder}/${config.hostSpec.hostName}.yaml";
          owner = "prowlarr";
          group = "prowlarr";
          mode = "0400";
        };
        sops.secrets."prowlarr/indexer-e/api-key" = {
          sopsFile = "${sopsFolder}/${config.hostSpec.hostName}.yaml";
          owner = "prowlarr";
          group = "prowlarr";
          mode = "0400";
        };
        sops.secrets."prowlarr/indexer-f/api-key" = {
          sopsFile = "${sopsFolder}/${config.hostSpec.hostName}.yaml";
          owner = "prowlarr";
          group = "prowlarr";
          mode = "0400";
        };

        # Container definition
        containers.prowlarr = {
          autoStart = true;
          ephemeral = true;

          bindMounts = {
            "/var/lib/prowlarr" = {
              hostPath = cfg.dataDir;
              isReadOnly = false;
            };
            "/run/secrets/prowlarr/api-key" = {
              hostPath = config.sops.secrets."prowlarr/api-key".path;
              isReadOnly = true;
            };
            "/run/secrets/prowlarr/password" = {
              hostPath = config.sops.secrets."prowlarr/password".path;
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
            "/run/secrets/prowlarr/indexer-a/api-key" = {
              hostPath = config.sops.secrets."prowlarr/indexer-a/api-key".path;
              isReadOnly = true;
            };
            "/run/secrets/prowlarr/indexer-b/api-key" = {
              hostPath = config.sops.secrets."prowlarr/indexer-b/api-key".path;
              isReadOnly = true;
            };
            "/run/secrets/prowlarr/indexer-b/rss-key" = {
              hostPath = config.sops.secrets."prowlarr/indexer-b/rss-key".path;
              isReadOnly = true;
            };
            "/run/secrets/prowlarr/indexer-c/api-key" = {
              hostPath = config.sops.secrets."prowlarr/indexer-c/api-key".path;
              isReadOnly = true;
            };
            "/run/secrets/prowlarr/indexer-d/api-key" = {
              hostPath = config.sops.secrets."prowlarr/indexer-d/api-key".path;
              isReadOnly = true;
            };
            "/run/secrets/prowlarr/indexer-e/api-key" = {
              hostPath = config.sops.secrets."prowlarr/indexer-e/api-key".path;
              isReadOnly = true;
            };
            "/run/secrets/prowlarr/indexer-f/api-key" = {
              hostPath = config.sops.secrets."prowlarr/indexer-f/api-key".path;
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

              services.prowlarr = {
                enable = true;
                openFirewall = true;
                dataDir = "/var/lib/prowlarr";
                # openssl rand -hex 16
                apiKeyFile = "/run/secrets/prowlarr/api-key";
              };

              # Declarr configures prowlarr via API during runtime
              services.declarr = {
                enable = true;
                user = "prowlarr";
                group = "prowlarr";
                config = {
                  declarr = {
                    stateDir = "/var/lib/prowlarr";
                    globalResolvePaths = [
                      "$.*.config.host.password"
                      "$.*.config.host.passwordConfirmation"
                      "$.*.config.host.apiKey"
                      "$.*.applications.*.fields.apiKey"
                      "$.*.indexer.*.fields.apikey"
                      "$.*.indexer.*.fields.rsskey"
                    ];
                  };

                  prowlarr = {
                    declarr = {
                      type = "prowlarr";
                      url = "http://localhost:${toString cfg.port}";
                    };
                    config.host = {
                      apiKey = "/run/secrets/prowlarr/api-key";
                      authenticationMethod = "forms";
                      authenticationRequired = "disabledForLocalAddresses";
                      username = "bungo";
                      password = config.sops.secrets."prowlarr/password".path;
                      passwordConfirmation = config.sops.secrets."prowlarr/password".path;
                    };

                    # Honestly just yoinked this from https://github.com/xhos/nix/blob/main/modules/nixos/opt/_enrai/services/media/prowlarr.nix
                    appProfile.Standard = {
                      enableRss = true;
                      enableAutomaticSearch = true;
                      enableInteractiveSearch = true;
                      minimumSeeders = 1;
                    };

                    indexer = indexers;

                    indexerProxy = { }; # This is a requirement? Why not default??
                    applications = {
                      Sonarr = {
                        implementation = "Sonarr";
                        syncLevel = "fullSync";
                        fields = {
                          prowlarrUrl = "http://${net.containerIP}:${toString cfg.port}";
                          baseUrl = "http://${
                            (lib.custom.mkContainerNetworkConfig config cfg.network "sonarr").containerIP
                          }:${toString config.custom.services.sonarr.port}";
                          apiKey = "/run/secrets/sonarr/api-key";
                        };
                      };
                      Radarr = {
                        implementation = "Radarr";
                        syncLevel = "fullSync";
                        fields = {
                          prowlarrUrl = "http://${net.containerIP}:${toString cfg.port}";
                          baseUrl = "http://${
                            (lib.custom.mkContainerNetworkConfig config cfg.network "radarr").containerIP
                          }:${toString config.custom.services.radarr.port}";
                          apiKey = "/run/secrets/radarr/api-key";
                        };
                      };
                    };
                  };
                };
              };

              # Override prowlarr systemd service to work with bind-mounted data dir
              systemd.services.prowlarr.serviceConfig = {
                DynamicUser = lib.mkForce false;
                User = "prowlarr";
                Group = "prowlarr";
                StateDirectory = lib.mkForce "";
              };

              # Override declarr systemd deps
              systemd.services.declarr = {
                after = lib.mkForce [
                  "network.target"
                  "prowlarr.service"
                ];
                wants = lib.mkForce [ "prowlarr.service" ];
                wantedBy = lib.mkForce [ "multi-user.target" ];
                serviceConfig = {
                  Restart = "on-failure";
                  RestartSec = "5s";
                };
              };

              # Container user/group
              users.users.prowlarr = {
                isSystemUser = true;
                group = lib.mkForce "prowlarr";
                uid = lib.mkForce cfg.uid;
                extraGroups = [ "media" ];
              };
              users.groups.prowlarr.gid = lib.mkForce cfg.gid;
              users.groups.media.gid = 5000;
            }
          ];
        };
      }
    ]
  );
}
