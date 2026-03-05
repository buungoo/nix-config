# Netbird client configuration
{
  config,
  pkgs,
  lib,
  isDarwin ? false,
  ...
}:
let
  cfg = config.custom.services.netbird-client;
in
{
  options.custom.services.netbird-client = {
    enable = lib.mkEnableOption "Netbird client";

    # Allow clients to set their own name, defaults to hostname
    name = lib.mkOption {
      type = lib.types.str;
      default = config.hostSpec.hostName;
      description = "Netbird client name (used for interface and service name)";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 51821;
      description = "Netbird client port";
    };

    managementURL = lib.mkOption {
      type = lib.types.str;
      description = "Netbird management URL";
      example = "https://netbird.example.com";
    };

    setupKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to the Netbird setup key file for automatic login.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        # Install the Netbird package on all systems
        environment.systemPackages = [ pkgs.netbird ];
      }

      (lib.optionalAttrs (!isDarwin) {
        # NixOS client configuration
        services.netbird.clients."${cfg.name}" = {
          port = cfg.port;
          interface = "nb-${cfg.name}";
          logLevel = "info";
          config = {
            ManagementURL = {
              Scheme = "https";
              Host = (builtins.elemAt (lib.splitString "://" cfg.managementURL) 1);
            };
          };
          login = lib.optionalAttrs (cfg.setupKeyFile != null) {
            enable = true;
            setupKeyFile = cfg.setupKeyFile;
          };
        };

        # Allow primary users to talk to the NetBird daemon socket.
        users.users = lib.mapAttrs (name: user: {
          extraGroups = [ "netbird-${cfg.name}" ];
        }) (lib.filterAttrs (name: user: user.primary or false) config.hostSpec.users);

        # State directory permissions for login
        systemd.services."netbird-${cfg.name}".serviceConfig.StateDirectoryMode = lib.mkForce "0750";

        # Point the CLI to the correct socket for this named client
        environment.variables.NETBIRD_DAEMON_ADDR = "unix:///var/run/netbird-${cfg.name}/sock";

        networking.firewall.allowedUDPPorts = [ cfg.port ];
      })

      (lib.optionalAttrs isDarwin {
        # Darwin setup
        system.activationScripts.postActivation.text = ''
          echo "ensuring netbird runtime directory..."
          mkdir -p /var/run/netbird
          chmod 755 /var/run/netbird
        '';

        launchd.daemons.netbird = {
          command = "${pkgs.netbird}/bin/netbird service run";
          serviceConfig = {
            Label = "io.netbird.client";
            RunAtLoad = true;
            KeepAlive = true;
            StandardErrorPath = "/var/log/netbird.err.log";
            StandardOutPath = "/var/log/netbird.out.log";
          };
        };
      })
    ]
  );
}
