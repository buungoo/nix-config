# WireGuard client configuration for connecting to nas0
{
  config,
  lib,
  inputs,
  pkgs,
  isDarwin ? false,
  ...
}:
let
  # Find the primary user
  primaryUser = builtins.head (
    lib.attrNames (lib.filterAttrs (_: user: user.primary or false) config.hostSpec.users)
  );
in
{
  # Add sops secret for WireGuard private key
  sops.secrets."wireguard/private_key" = {
    sopsFile = (builtins.toString inputs.nix-secrets) + "/sops/${config.hostSpec.hostName}.yaml";
    owner = primaryUser;
    mode = "0400";
  };

  environment.systemPackages = [
    pkgs.wireguard-tools
  ];
}
// lib.optionalAttrs (!isDarwin) {
  # WireGuard client configuration using wg-quick
  networking.wg-quick.interfaces.wg0 = {
    # Client IP in the VPN subnet
    address = [ "10.100.0.4/24" ];

    privateKeyFile = config.sops.secrets."wireguard/private_key".path;

    # Configure nas0 and nas1 as peers
    peers = [
      {
        # nas0 server
        publicKey = inputs.nix-secrets.nas0.wireguard.publicKey;

        # Allow traffic to nas0's WireGuard IP and local network
        allowedIPs = [
          "10.100.0.1/32" # nas0 WireGuard IP
          "192.168.1.0/24" # nas0 local network
          "10.0.0.0/16" # container subnets (arr, immich, kanidm, dns, ca, mon)
        ];

        # Endpoint: nas0's domain
        endpoint = "${inputs.nix-secrets.nas0.domain}:51820";

        # Keep connection alive
        persistentKeepalive = 25;
      }
    ];
  };

  networking.wg-quick.interfaces.wg1 = {
    # Client IP in the VPN subnet
    address = [ "10.100.0.4/24" ];

    privateKeyFile = config.sops.secrets."wireguard/private_key".path;

    peers = [
      {
        # nas1 server
        publicKey = inputs.nix-secrets.nas1.wireguard.publicKey;

        # Allow traffic to nas1's WireGuard IP and local network
        allowedIPs = [
          "${inputs.nix-secrets.nas1.networking.wireguardIP}/32" # nas1 WireGuard IP
          "${inputs.nix-secrets.nas1.networking.localSubnet}" # nas1 local network
        ];

        # Endpoint: nas1's domain
        endpoint = "${inputs.nix-secrets.nas1.domain}:51820";

        # Keep connection alive
        persistentKeepalive = 25;
      }
    ];
  };

  # NOTE: Remove this after server migration
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
  networking.firewall.allowedTCPPorts = [ 8096 ];
  networking.nftables = {
    enable = true;
    tables.jellyfin-forward = {
      family = "ip";
      content = ''
        chain prerouting {
          type nat hook prerouting priority dstnat; policy accept;
          tcp dport 8096 dnat to 10.0.1.2:8096
        }
        chain forward {
          type filter hook forward priority filter; policy accept;
          ip daddr 10.0.1.2 tcp dport 8096 oifname "wg0" counter accept
          ct state established,related counter accept
        }
        chain postrouting {
          type nat hook postrouting priority srcnat; policy accept;
          ip daddr 10.0.1.2 oifname "wg0" masquerade
        }
      '';
    };
  };
}
// lib.optionalAttrs isDarwin {
  # WireGuard client configuration using wg-quick
  networking.wg-quick.interfaces.wg0 = {
    # Client IP in the VPN subnet
    address = [ "10.100.0.3/24" ];

    privateKeyFile = config.sops.secrets."wireguard/private_key".path;

    # Configure nas0 and nas1 as peers
    peers = [
      {
        # nas0 server
        publicKey = inputs.nix-secrets.nas0.wireguard.publicKey;

        # Allow traffic to nas0's WireGuard IP and local network
        allowedIPs = [
          "10.100.0.1/32" # nas0 WireGuard IP
          "192.168.1.0/24" # nas0 local network
          "10.0.0.0/16" # container subnets (arr, immich, kanidm, dns, ca, mon)
        ];

        # Endpoint: nas0's domain
        endpoint = "${inputs.nix-secrets.nas0.domain}:51820";

        # Keep connection alive
        persistentKeepalive = 25;
      }
    ];
  };

  networking.wg-quick.interfaces.wg1 = {
    # Client IP in the VPN subnet
    address = [ "10.100.0.3/24" ];

    privateKeyFile = config.sops.secrets."wireguard/private_key".path;

    peers = [
      {
        # nas1 server
        publicKey = inputs.nix-secrets.nas1.wireguard.publicKey;

        # Allow traffic to nas1's WireGuard IP and local network
        allowedIPs = [
          "${inputs.nix-secrets.nas1.networking.wireguardIP}/32" # nas1 WireGuard IP
          "${inputs.nix-secrets.nas1.networking.localSubnet}" # nas1 local network
        ];

        # Endpoint: nas1's domain
        endpoint = "${inputs.nix-secrets.nas1.domain}:51820";

        # Keep connection alive
        persistentKeepalive = 25;
      }
    ];
  };

  # Override the launchd daemon to disable KeepAlive (macOS only)
  # This allows wg-quick down to actually stop the interface
  launchd.daemons.wg-quick-wg0.serviceConfig.KeepAlive = lib.mkForce false;
  launchd.daemons.wg-quick-wg1.serviceConfig.KeepAlive = lib.mkForce false;
}
