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

    disableDNS = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to disable Netbird DNS management.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        # Install the Netbird package on Darwin only (NixOS uses a wrapper below)
        environment.systemPackages =
          (lib.optional isDarwin pkgs.netbird) ++ (lib.optional (!isDarwin) pkgs.openresolv);
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

        # Enable systemd-resolved to allow Netbird to push DNS updates via DBus
        # without needing to modify the read-only /etc/resolv.conf directly.
        services.resolved.enable = lib.mkIf (!cfg.disableDNS) true;

        # Allow primary users to talk to the NetBird daemon socket.
        users.users = lib.mapAttrs (name: user: {
          extraGroups = [ "netbird-${cfg.name}" ];
        }) (lib.filterAttrs (name: user: user.primary or false) config.hostSpec.users);

        # State directory permissions for login
        systemd.services."netbird-${cfg.name}" = {
          serviceConfig = {
            StateDirectoryMode = lib.mkForce "0750";

            # Fix "Required key not available" and read-only FS errors
            # Force userspace WireGuard (software) which is more reliable on some NixOS kernels
            # Disable SSH for now to avoid errors with read-only /etc
            Environment = [
              "NB_WG_IFACE_TYPE=software"
              "NB_DISABLE_SSH_AUTH=true"
              "NB_DISABLE_DNS=${if cfg.disableDNS then "true" else "false"}"
            ];

            # Allow netbird to update DNS and SSH if we ever want to enable them
            # and to avoid errors during cleanup
            ReadWritePaths = [
              "/etc/ssh"
            ] ++ (lib.optional (!cfg.disableDNS) "/etc/resolv.conf");

            # Ensure we have enough permissions for network management
            AmbientCapabilities = [
              "CAP_NET_ADMIN"
              "CAP_NET_RAW"
              "CAP_BPF"
              "CAP_SYS_ADMIN"
            ];
          };
        };

        # Point the CLI to the correct socket for this named client
        environment.sessionVariables.NETBIRD_DAEMON_ADDR = "unix:///var/run/netbird-${cfg.name}/sock";

        # Provide a wrapped netbird command that always uses the correct socket
        # We use a higher priority script to ensure it's picked up over the default binary
        environment.systemPackages = [
          (lib.hiPrio (
            pkgs.writeShellScriptBin "netbird" ''
              exec ${pkgs.netbird}/bin/netbird --daemon-addr "unix:///var/run/netbird-${cfg.name}/sock" "$@"
            ''
          ))
        ];

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
            EnvironmentVariables = {
              NB_WG_IFACE_TYPE = "software";
              NB_DISABLE_SSH_AUTH = "true";
              NB_DISABLE_DNS = if cfg.disableDNS then "true" else "false";
            };
          };
        };
      })
    ]
  );
}
