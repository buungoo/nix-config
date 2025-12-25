# WireGuard client configuration for connecting to nas0
{
  config,
  lib,
  inputs,
  ...
}:
let
  # Find the primary user
  primaryUser = builtins.head (
    lib.attrNames (lib.filterAttrs (_: user: user.primary or false) config.hostSpec.users)
  );
in
{
  # WireGuard client configuration using wg-quick
  networking.wg-quick.interfaces = {
    wg0 = {
      # Client IP in the VPN subnet
      address = [ "10.100.0.3/24" ];

      # Client private key (managed via sops-nix)
      privateKeyFile = config.sops.secrets."wireguard/private_key".path;

      # Configure nas0 as the peer
      peers = [
        {
          # nas0 server
          publicKey = inputs.nix-secrets.nas0.wireguard.publicKey;

          # Allow traffic to nas0's WireGuard IP and local network
          allowedIPs = [
            "10.100.0.1/32"  # nas0 WireGuard IP
            "192.168.1.0/24" # nas0 local network
          ];

          # Endpoint: nas0's domain
          endpoint = "${inputs.nix-secrets.nas0.domain}:51820";

          # Keep connection alive
          persistentKeepalive = 25;
        }
      ];
    };
  };

  # Add sops secret for WireGuard private key
  sops.secrets."wireguard/private_key" = {
    sopsFile = (builtins.toString inputs.nix-secrets) + "/sops/${config.hostSpec.hostName}.yaml";
    owner = primaryUser;
    mode = "0400";
  };

  # Override the launchd daemon to disable KeepAlive
  # This allows wg-quick down to actually stop the interface
  launchd.daemons.wg-quick-wg0.serviceConfig.KeepAlive = lib.mkForce false;
}
