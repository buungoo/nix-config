# WireGuard client configuration for connecting to nas0
{
  config,
  lib,
  inputs,
  ...
}:
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
          endpoint = "${inputs.nix-secrets.shared.domain}:51820";

          # Keep connection alive
          persistentKeepalive = 25;
        }
      ];
    };
  };

  # Add sops secret for WireGuard private key
  sops.secrets."wireguard/private_key" = {
    sopsFile = (builtins.toString inputs.nix-secrets) + "/sops/${config.hostSpec.hostName}.yaml";
    owner = config.hostSpec.primaryUser;
    mode = "0400";
  };
}
