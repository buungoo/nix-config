# File: qbittorrent.nix
# What: Torrent dirs
# Permissions: 2775
# Owner: qbittorrent:media
# Why: Setgid inherits media group; group write for hardlinks
# ────────────────────────────────────────
# File: qbittorrent.nix
# What: UMask
# Permissions: 0002
# Owner: —
# Why: Files created as 0664, dirs as 2775
# ────────────────────────────────────────
# File: sonarr.nix
# What: /arr/media/tv
# Permissions: 0755
# Owner: sonarr:media
# Why: Sonarr owns dir (can add/delete/rename); group read-only
# ────────────────────────────────────────
# File: radarr.nix
# What: /arr/media/movies
# Permissions: 0755
# Owner: radarr:media
# Why: Radarr owns dir; group read-only
# ────────────────────────────────────────
# File: sonarr/radarr
# What: SetPermissionsLinux
# Permissions: false
# Owner: —
# Why: Don't touch file permissions; qbittorrent's 0664 is source of truth
# ────────────────────────────────────────
# File: jellyfin.nix
# What: No media dirs
# Permissions: —
# Owner: —
# Why: Only reads via media group
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  cfg = config.custom.services.qbittorrent;
  net = lib.custom.mkContainerNetworkConfig config cfg.network "qbittorrent";

  uid = toString cfg.uid;
  gid = toString cfg.gid;
  mediaGid = 5000;

  sopsFolder = builtins.toString inputs.nix-secrets + "/sops";
in
{
  options.custom.services.qbittorrent = {
    enable = lib.mkEnableOption "qBittorrent container with VueTorrent UI";

    uid = lib.mkOption {
      type = lib.types.int;
      default = 10400;
      description = "UID for qbittorrent user on both host and container";
    };

    gid = lib.mkOption {
      type = lib.types.int;
      default = 10400;
      description = "GID for qbittorrent group on both host and container";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "qbit.${config.hostSpec.domain}";
      description = "FQDN for the qBittorrent reverse proxy virtual host";
    };

    network = lib.mkOption {
      type = lib.types.str;
      default = "arr";
      description = "Which containerNetwork to place qbittorrent on";
    };

    hostOctet = lib.mkOption {
      type = lib.types.int;
      default = 7;
      description = "Host octet for the container IP in the network subnet.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "qBittorrent WebUI port";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/qbittorrent";
      description = "Host path for persistent qBittorrent application data";
    };

    torrentPath = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/storage/arr/torrents";
      description = "Host path to the torrents directory";
    };

    passwordSecret = lib.mkOption {
      type = lib.types.str;
      default = "qbit/password";
      description = "Sops secret name for the qBittorrent WebUI password";
    };

    serverConfig = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Additional qBittorrent serverConfig";
    };

    vpn = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable WireGuard tunnel for qBittorrent traffic";
      };

      privateKeySecret = lib.mkOption {
        type = lib.types.str;
        default = "qbit/wg/private_key";
        description = "Sops secret name for the WireGuard private key";
      };

      address = lib.mkOption {
        type = lib.types.str;
        default = "10.2.0.2/32";
        description = "WireGuard interface address";
      };

      dns = lib.mkOption {
        type = lib.types.str;
        default = "10.2.0.1";
        description = "DNS server";
      };

      peer = {
        publicKey = lib.mkOption {
          type = lib.types.str;
          default = "JrE+gkEbcY1NU5Hhgc6lAGsP7YJmLykA1h2nSLfUJiM=";
          description = "WireGuard peer public key";
        };

        endpoint = lib.mkOption {
          type = lib.types.str;
          default = "169.150.196.67:51820";
          description = "WireGuard peer endpoint";
        };

        allowedIPs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "0.0.0.0/0"
            "::/0"
          ];
          description = "WireGuard peer allowed IPs";
        };
      };
    };
  };

  # Implementation
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.custom.mkContainerServiceConfig "qbittorrent" { })
      {
        # Create user on host
        users.users.qbittorrent = {
          isSystemUser = true;
          group = "qbittorrent";
          extraGroups = [ "media" ];
          uid = cfg.uid;
        };
        users.groups.qbittorrent.gid = cfg.gid;

        # Register reverse proxy
        custom.reverseProxy.virtualHosts.qbittorrent = {
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
          containers.qbittorrent = lib.mkDefault cfg.hostOctet;
        };

        # Setup bindmount directories
        systemd.tmpfiles.rules = [
          "d ${cfg.dataDir} 0755 ${uid} ${gid} -"
          "d ${cfg.torrentPath} 2775 ${uid} ${toString mediaGid} -"
          "d ${cfg.torrentPath}/books 2775 ${uid} ${toString mediaGid} -"
          "d ${cfg.torrentPath}/incomplete 2775 ${uid} ${toString mediaGid} -"
          "d ${cfg.torrentPath}/movies 2775 ${uid} ${toString mediaGid} -"
          "d ${cfg.torrentPath}/music 2775 ${uid} ${toString mediaGid} -"
          "d ${cfg.torrentPath}/tv 2775 ${uid} ${toString mediaGid} -"
        ];

        # Fetch secrets
        sops.secrets.${cfg.passwordSecret} = {
          sopsFile = "${sopsFolder}/${config.hostSpec.hostName}.yaml";
          owner = "qbittorrent";
          group = "qbittorrent";
          mode = "0400";
        };
        sops.secrets."qbit/plaintext_password" = {
          sopsFile = "${sopsFolder}/${config.hostSpec.hostName}.yaml";
          owner = "qbittorrent";
          group = "media";
          mode = "0440";
        };
        sops.secrets.${cfg.vpn.privateKeySecret} = lib.mkIf cfg.vpn.enable {
          sopsFile = "${sopsFolder}/${config.hostSpec.hostName}.yaml";
          owner = "root";
          group = "root";
          mode = "0400";
        };

        # Container definition
        containers.qbittorrent = {
          autoStart = true;
          ephemeral = true;

          bindMounts = lib.mkMerge [
            {
              "/var/lib/qbittorrent" = {
                hostPath = cfg.dataDir;
                isReadOnly = false;
              };
              "/arr/torrents" = {
                hostPath = cfg.torrentPath;
                isReadOnly = false;
              };
              "/run/secrets/${cfg.passwordSecret}" = {
                hostPath = config.sops.secrets.${cfg.passwordSecret}.path;
                isReadOnly = true;
              };
              "/run/secrets/qbit/plaintext_password" = {
                hostPath = config.sops.secrets."qbit/plaintext_password".path;
                isReadOnly = true;
              };
            }
            (lib.mkIf cfg.vpn.enable {
              "/run/secrets/${cfg.vpn.privateKeySecret}" = {
                hostPath = config.sops.secrets.${cfg.vpn.privateKeySecret}.path;
                isReadOnly = true;
              };
            })
          ];

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
            (lib.custom.mkContainerBaseConfig (
              net
              // {
                inherit (config.hostSpec) stateVersion;
                dns = lib.optional cfg.vpn.enable cfg.vpn.dns ++ [ "1.1.1.1" ];
              }
            ))
            {
              environment.systemPackages = with pkgs; [ libnatpmp ];

              # VPN configuration
              # Route container network traffic via bridge, not VPN
              # Uses specific subnet instead of 10.0.0.0/8 to avoid capturing VPN gateway (10.2.0.1)
              networking.localCommands = lib.mkIf cfg.vpn.enable ''
                ip route add ${net.networkCfg.subnet} via ${net.gatewayIP} dev eth0 table main priority 100
                ip route add 192.168.0.0/16 via ${net.gatewayIP} dev eth0 table main priority 100
                ip route add 172.16.0.0/12 via ${net.gatewayIP} dev eth0 table main priority 100
              '';

              networking.wg-quick.interfaces.wg0 = lib.mkIf cfg.vpn.enable {
                privateKeyFile = "/run/secrets/${cfg.vpn.privateKeySecret}";
                address = [ cfg.vpn.address ];
                autostart = true;
                peers = [
                  {
                    publicKey = cfg.vpn.peer.publicKey;
                    endpoint = cfg.vpn.peer.endpoint;
                    allowedIPs = cfg.vpn.peer.allowedIPs;
                    persistentKeepalive = 25;
                  }
                ];
              };

              # qBittorrent service
              services.qbittorrent = {
                enable = true;
                openFirewall = true;
                user = "qbittorrent";
                group = "media";
                webuiPort = cfg.port;
                profileDir = "/var/lib/qbittorrent";
                # Great resource for configuring qbit (together with trash)
                # https://www.samkwort.com/qbittorrent_nixos_module
                serverConfig = lib.mkMerge [
                  {
                    LegalNotice.Accepted = true;
                    Core.AutoDeleteAddedTorrentFile = "IfAdded";
                    Network.PortForwardingEnabled = false; # Disable upnp
                    Preferences.WebUI = {
                      Username = "bungo";
                      Password_PBKDF2 = "PLACEHOLDER"; # Replaced by ExecStartPre with value from sops
                      AlternativeUIEnabled = true;
                      RootFolder = "${pkgs.vuetorrent}/share/vuetorrent";
                    };
                    BitTorrent = {
                      PortForwardingEnabled = false;
                      Session = {
                        BTProtocol = "TCP";
                        Interface = lib.mkIf cfg.vpn.enable "wg0";
                        InterfaceName = lib.mkIf cfg.vpn.enable "wg0";
                        DefaultSavePath = "/arr/torrents";
                        TempPath = "/arr/torrents/incomplete";
                        TempPathEnabled = true;
                        DisableAutoTMMByDefault = false; # Automatic torrent management mode
                        DisableAutoTMMTriggers.CategorySavePathChanged = false;
                        DisableAutoTMMTriggers.DefaultSavePathChanged = false;
                        # Might cause ddos protection by vpn ?
                        # This was from 2 years ago but let's assume this is still the case:
                        # https://www.reddit.com/r/ProtonVPN/comments/1eowoxt/tip_dht_will_trigger_protonvpn_antiddos_disable_it/
                        DHTEnabled = false;
                        GlobalDLSpeedLimit = 25000; # KB/s
                        GlobalUPSpeedLimit = 25000;
                        UseAlternativeGlobalSpeedLimit = false;
                        MaxActiveCheckingTorrents = 4; # Should be fine (with overhead) on all nvme nas
                        # Port = This is set dynamically by the qbit-portforward script

                        # Set to -1 to disable
                        MaxConnections = 2000; # Max peers from all torrents combined
                        MaxConnectionsPerTorrent = 60; # Max peers for a singular torrent

                        MaxUploads = 50; # Max peers we are actively uploading to
                        MaxUploadsPerTorrent = 6; # Max peers uploading to for a single torrent

                        QueueingSystemEnabled = true;
                        MaxActiveTorrents = 400;
                        MaxActiveDownloads = 20;
                        MaxActiveUploads = 380;

                        IgnoreSlowTorrentsForQueueing = true;
                        SlowTorrentsDownloadRate = 500;
                        SlowTorrentsUploadRate = 500;
                      };
                    };
                    Preferences.WebUI.ClickjackingProtection = false;
                  }
                  cfg.serverConfig
                ];
              };

              systemd.services.qbittorrent = lib.mkMerge [
                {
                  # UMask 0002 creates files as 0664 (group-writable), required for
                  # sonarr/radarr hardlinks due to fs.protected_hardlinks
                  serviceConfig.UMask = "0002";
                  # Inject password from sops into config after the module's preStart writes serverConfig
                  # mkAfter ensures this runs after the INI generator, which quotes @ByteArray() breaking Qt
                  preStart = lib.mkAfter ''
                    CONF="/var/lib/qbittorrent/qBittorrent/config/qBittorrent.conf"
                    HASH=$(cat /run/secrets/${cfg.passwordSecret})
                    ${pkgs.gnused}/bin/sed -i "s|Password_PBKDF2=.*|Password_PBKDF2=@ByteArray($HASH)|" "$CONF"
                  '';
                }
                # qbittorrent must wait for VPN
                (lib.mkIf cfg.vpn.enable {
                  after = [
                    "network.target"
                    "wg-quick-wg0.service"
                  ];
                  wants = [ "wg-quick-wg0.service" ];
                })
              ];

              # NAT-PMP port forwarding for ProtonVPN
              systemd.services.qbit-portforward = lib.mkIf cfg.vpn.enable {
                description = "Renew ProtonVPN port forwarding for qBittorrent";
                after = [
                  "wg-quick-wg0.service"
                  "qbittorrent.service"
                ];
                wants = [ "wg-quick-wg0.service" ];
                serviceConfig = {
                  Type = "oneshot";
                  ExecStart = pkgs.writeShellScript "qbit-portforward" ''
                    PORT=$(${pkgs.libnatpmp}/bin/natpmpc -a 1 0 tcp 60 -g ${cfg.vpn.dns} \
                      | ${pkgs.gnugrep}/bin/grep 'Mapped public port' \
                      | ${pkgs.gawk}/bin/awk '{print $4}')

                    if [ -z "$PORT" ]; then
                      echo "Failed to get port from NAT-PMP"
                      exit 1
                    fi

                    # Also map UDP
                    ${pkgs.libnatpmp}/bin/natpmpc -a 1 0 udp 60 -g ${cfg.vpn.dns}

                    # Authenticate and update qBittorrent listening port
                    PASSWORD=$(cat /run/secrets/qbit/plaintext_password)
                    COOKIE=$(mktemp)
                    ${pkgs.curl}/bin/curl -s -b "$COOKIE" -c "$COOKIE" \
                      http://localhost:${toString cfg.port}/api/v2/auth/login \
                      -d "username=bungo&password=$PASSWORD"
                    ${pkgs.curl}/bin/curl -s -b "$COOKIE" \
                      http://localhost:${toString cfg.port}/api/v2/app/setPreferences \
                      -d "json={\"listen_port\":$PORT}"
                    rm -f "$COOKIE"

                    echo "Forwarded public port $PORT"
                  '';
                };
              };
              systemd.timers.qbit-portforward = lib.mkIf cfg.vpn.enable {
                wantedBy = [ "timers.target" ];
                timerConfig = {
                  OnBootSec = "30s";
                  OnUnitActiveSec = "45s";
                };
              };

              # Container user/group
              # mkForce needed: services.qbittorrent sets group to cfg.group ("media")
              users.users.qbittorrent = {
                isSystemUser = true;
                uid = cfg.uid;
                group = lib.mkForce "qbittorrent";
                extraGroups = [ "media" ];
                home = "/var/lib/qbittorrent";
                createHome = true;
              };
              users.groups.qbittorrent.gid = cfg.gid;
              users.groups.media.gid = mediaGid;
            }
          ];
        };
      }
    ]
  );
}
