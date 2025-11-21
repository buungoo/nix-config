# Specifications For Differentiating Hosts
{
  config,
  pkgs,
  lib,
  ...
}:
{
  options.hostSpec = {
    # Basic host identification
    stateVersion = lib.mkOption {
      description = "Initial state version of the machine";
      type = lib.types.str;
      example = "24.11";
    };

    hostName = lib.mkOption {
      description = "The hostname of the host";
      type = lib.types.str;
      example = "nas0";
    };

    hostAlias = lib.mkOption {
      description = "Alias/friendly name of the host";
      type = lib.types.str;
      example = "NixOS Server";
    };

    # Primary domain for this infrastructure
    domain = lib.mkOption {
      description = "Primary domain name for services";
      type = lib.types.str;
      example = "example.com";
    };

    # Service domain mappings
    domains = lib.mkOption {
      description = "Domain names and configuration for each service";
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          {
            options = {
              domain = lib.mkOption {
                type = lib.types.str;
                description = "Domain name for ${name}";
              };
              public = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Whether this service is exposed to WAN (requires mTLS if true)";
              };
              backendHost = lib.mkOption {
                type = lib.types.str;
                description = "Backend host IP address for ${name}";
              };
              backendPort = lib.mkOption {
                type = lib.types.port;
                description = "Backend port for ${name}";
              };
              backendSSL = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Whether the backend uses SSL";
              };
            };
          }
        )
      );
      default = { };
      example = {
        immich = {
          domain = "immich.domanin.tld";
          public = true;
          backendHost = "10.0.0.2";
          backendPort = 2283;
          backendSSL = false;
        };
        scrutiny = {
          domain = "scrutiny.domain.tld";
          public = false;
          backendHost = "0.0.0.0";
          backendPort = 5532;
          backendSSL = false;
        };
      };
    };

    # Declarative users
    users = lib.mkOption {
      description = "Declarative user definitions for this host";
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          {
            options = {
              fullName = lib.mkOption {
                description = "Real name for user `${name}`";
                type = lib.types.str;
              };

              userEmail = lib.mkOption {
                description = "Primary e-mail address for `${name}`";
                type = lib.types.str;
              };

              githubUsername = lib.mkOption {
                description = "GitHub username for `${name}`";
                type = lib.types.str;
              };

              groups = lib.mkOption {
                description = "Groups for `${name}`";
                type = lib.types.listOf lib.types.str;
                default = [ ];
              };

              isSystemUser = lib.mkOption {
                description = "Whether this is a system user";
                type = lib.types.bool;
                default = false;
              };

              shell = lib.mkOption {
                description = "Default shell for the user";
                type = lib.types.str;
                default = "zsh";
              };

              home = lib.mkOption {
                description = "Home directory for user `${name}`. Defaults to /home/\${name} on Linux, /Users/\${name} on macOS";
                type = lib.types.str;
                default = if pkgs.stdenv.isLinux then "/home/${name}" else "/Users/${name}";
              };

              isAdmin = lib.mkOption {
                description = "Whether `${name}` is an administrator (grants admin access to services like Grafana, Jellyfin, etc.)";
                type = lib.types.bool;
                default = false;
              };

              primary = lib.mkOption {
                description = "Whether `${name}` is the primary user";
                type = lib.types.bool;
                default = false;
              };
            };
          }
        )
      );
      default = { };
      example = {
        bungo = {
          fullName = "Bungo User";
          userEmail = "bungo@example.com";
          groups = [
            "wheel"
            "networkmanager"
            "docker"
          ];
          primary = true;
        };
      };
    };

    # Service-specific user configurations
    services = lib.mkOption {
      description = "Service-specific user and configuration definitions";
      default = { };
      type = lib.types.submodule {
        options = {
          jellyfin = lib.mkOption {
            description = "Jellyfin service configuration";
            default = { };
            type = lib.types.submodule {
              options = {
                users = lib.mkOption {
                  description = "Jellyfin application users";
                  default = { };
                  type = lib.types.attrsOf (
                    lib.types.submodule (
                      { name, ... }:
                      {
                        options = {
                          systemUser = lib.mkOption {
                            type = lib.types.nullOr lib.types.str;
                            default = null;
                            description = "Reference to system user in hostSpec.users (inherits email if set)";
                            example = "bungo";
                          };
                          isAdmin = lib.mkOption {
                            type = lib.types.bool;
                            default = false;
                            description = "Whether ${name} has administrator privileges in Jellyfin";
                          };
                        };
                      }
                    )
                  );
                  example = {
                    bungo = {
                      systemUser = "bungo";
                      isAdmin = true;
                    };
                    family = {
                      isAdmin = false;
                    };
                  };
                };
              };
            };
          };

          kanidm = lib.mkOption {
            description = "Kanidm identity provider configuration";
            default = { };
            type = lib.types.submodule {
              options = {
                users = lib.mkOption {
                  description = "Kanidm user accounts (mapped to 'persons' in Kanidm)";
                  default = { };
                  type = lib.types.attrsOf (
                    lib.types.submodule (
                      { name, ... }:
                      {
                        options = {
                          systemUser = lib.mkOption {
                            type = lib.types.nullOr lib.types.str;
                            default = null;
                            description = "Reference to system user in hostSpec.users (inherits email, fullName if set)";
                            example = "bungo";
                          };
                          displayName = lib.mkOption {
                            type = lib.types.str;
                            description = "Display name for ${name}";
                            example = "John Doe";
                          };
                          mailAddresses = lib.mkOption {
                            type = lib.types.listOf lib.types.str;
                            description = "Email addresses for ${name}";
                            example = [ "user@example.com" ];
                          };
                          groups = lib.mkOption {
                            type = lib.types.listOf lib.types.str;
                            default = [ ];
                            description = "Kanidm groups that ${name} belongs to (e.g., 'immich_users', 'oauth2-proxy_users')";
                            example = [
                              "immich_users"
                              "jellyfin_users"
                            ];
                          };
                        };
                      }
                    )
                  );
                  example = {
                    bungo = {
                      systemUser = "bungo";
                      displayName = "Bungo User";
                      mailAddresses = [ "bungo@example.com" ];
                      groups = [
                        "immich_users"
                        "oauth2-proxy_users"
                      ];
                    };
                  };
                };

                groups = lib.mkOption {
                  description = "Kanidm group definitions (members should be specified in user.groups)";
                  type = lib.types.attrsOf (
                    lib.types.submodule {
                      options = {
                        members = lib.mkOption {
                          type = lib.types.listOf lib.types.str;
                          default = [ ];
                          description = "Group members";
                        };
                      };
                    }
                  );
                  default = { };
                  example = {
                    immich_users.members = [
                      "bungo"
                      "friend"
                    ];
                  };
                };
              };
            };
          };
        };
      };
    };

    networking = lib.mkOption {
      default = { };
      description = "Networking configuration for this host.";
      type = lib.types.submodule (
        { ... }:
        {
          freeformType = lib.types.attrsOf lib.types.anything;
          options = {
            externalInterfaces = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              description = "External network interfaces for NAT, routing, and container access. First interface is used as primary.";
              example = [
                "enp3s0"
                "enp4s0"
              ];
            };

            dnsServers = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [
                "1.1.1.1"
                "8.8.8.8"
              ];
              description = "DNS servers for host and containers.";
              example = [
                "1.1.1.1"
                "8.8.8.8"
              ];
            };

            localIP = lib.mkOption {
              type = lib.types.str;
              description = "Local IP address for this host on the LAN";
              example = "10.0.0.10";
            };

            localSubnet = lib.mkOption {
              type = lib.types.str;
              description = "Local subnet CIDR for LAN";
              example = "10.0.0.0/24";
            };

            localIPv6Subnet = lib.mkOption {
              type = lib.types.str;
              description = "Local IPv6 subnet";
              example = "fd00::/64";
            };

            wireguardIPv4Subnet = lib.mkOption {
              type = lib.types.str;
              description = "WireGuard VPN IPv4 subnet";
              example = "10.100.0.0/24";
            };

            wireguardIPv6Subnet = lib.mkOption {
              type = lib.types.str;
              description = "WireGuard VPN IPv6 subnet";
              example = "fd01::/64";
            };

            containerNetworks = lib.mkOption {
              type = lib.types.attrsOf (
                lib.types.submodule (
                  { name, ... }:
                  {
                    options = {
                      bridge = lib.mkOption {
                        type = lib.types.str;
                        description = "Name of the bridge interface to create for ${name}.";
                      };
                      subnet = lib.mkOption {
                        type = lib.types.str;
                        description = "CIDR subnet for ${name}.";
                      };
                      gateway = lib.mkOption {
                        type = lib.types.str;
                        description = "Gateway IP address for ${name}.";
                      };
                      containers = lib.mkOption {
                        type = lib.types.attrsOf (lib.types.either lib.types.str lib.types.int);
                        default = { };
                        description = "Static IP assignments for containers on ${name}. Use either full IPv4 addresses or the host octet for /24 networks.";
                      };
                    };
                  }
                )
              );
              default = { };
              description = "Per-container bridge definitions for declarative networking.";
            };
          };
        }
      );
    };

    # Configuration flags
    isMinimal = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Used to indicate a minimal host";
    };

    isServer = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Used to indicate a server host";
    };

    isDarwin = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Used to indicate a host that is darwin";
    };

    # GPU hardware configuration
    gpu = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.submodule {
          options = {
            renderDevice = lib.mkOption {
              type = lib.types.str;
              default = "/dev/dri/renderD128";
              description = "Path to the GPU render device for hardware acceleration";
              example = "/dev/dri/renderD128";
            };
            cardDevice = lib.mkOption {
              type = lib.types.str;
              default = "/dev/dri/card0";
              description = "Path to the GPU card device";
              example = "/dev/dri/card1";
            };
          };
        }
      );
      default = null;
      description = "GPU hardware configuration for containers and services";
      example = {
        renderDevice = "/dev/dri/renderD128";
        cardDevice = "/dev/dri/card1";
      };
    };
  };

  # Computed values and validation
  config = {
    # Automatically populate Kanidm groups from user.groups
    hostSpec.services.kanidm.groups = lib.mkDefault (
      let
        # Collect all unique group names from all users
        allGroupNames = lib.unique (
          lib.flatten (
            lib.mapAttrsToList (_name: user: user.groups) config.hostSpec.services.kanidm.users
          )
        );

        # For each group, find all users that belong to it
        groupMembers = lib.genAttrs allGroupNames (
          groupName:
          lib.filterAttrs (
            _userName: user: builtins.elem groupName user.groups
          ) config.hostSpec.services.kanidm.users
        );
      in
      lib.mapAttrs (groupName: members: {
        members = builtins.attrNames members;
      }) groupMembers
    );

    assertions =
      let
        platform = if config.hostSpec.isDarwin then "darwin" else "nixos";

        # 1. every host must have hosts/<platform>/<hostName>
        hostDirExists = builtins.pathExists (
          lib.custom.relativeToRoot "hosts/${platform}/${config.hostSpec.hostName}"
        );

        # 2. every user must have home/<user>/<hostName>
        usersExist = builtins.all (
          user: builtins.pathExists (lib.custom.relativeToRoot "home/${user}/${config.hostSpec.hostName}")
        ) (builtins.attrNames config.hostSpec.users);

        # List of the ones that fail
        missingUsers = builtins.filter (
          u: !builtins.pathExists (lib.custom.relativeToRoot "home/${u}/${config.hostSpec.hostName}")
        ) (builtins.attrNames config.hostSpec.users);
      in
      [
        {
          assertion = hostDirExists;
          message = "hosts/${platform}/${config.hostSpec.hostName} is missing";
        }
        {
          assertion = usersExist || (builtins.length missingUsers == 0);
          message = "home/${builtins.elemAt missingUsers 0}/${config.hostSpec.hostName} is missing";
        }
        {
          assertion =
            let
              primaryUsers = lib.filterAttrs (_: user: user.primary or false) config.hostSpec.users;
              primaryCount = builtins.length (lib.attrNames primaryUsers);
            in
            primaryCount == 1;
          message = "Exactly one user must have primary = true in hostSpec.users";
        }
      ];
  };
}
