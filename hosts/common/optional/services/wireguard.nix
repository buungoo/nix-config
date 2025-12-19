# WireGuard VPN server configuration for remote access
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
{
  # WireGuard VPN network: 10.100.0.0/24
  networking.wireguard.interfaces = {
    wg0 = {
      # Server IP in the VPN subnet
      ips = [ "10.100.0.1/24" ];

      # WireGuard listen port
      listenPort = 51820;

      # Server private key (managed via sops-nix)
      privateKeyFile = config.sops.secrets."wireguard/private_key".path;

      # Add new clients by generating keypairs and adding entries here
      # wg genkey | tee client_private.key | wg pubkey > client_public.key
      peers = [
        {
          publicKey = "i8nNvuuU1r5a9HB5ntqTynRvnQkvktBTt2oyK2IGEgU=";
          allowedIPs = [ "10.100.0.2/32" ];
          persistentKeepalive = 25;
        }
        {
          # macbook
          publicKey = inputs.nix-secrets.macbook.wireguard.publicKey;
          allowedIPs = [ "10.100.0.3/32" ];
          persistentKeepalive = 25;
        }
      ];
    };
  };

  # Open WireGuard port in firewall
  networking.firewall.allowedUDPPorts = [ 51820 ];

  # Enable IP forwarding (required for routing VPN traffic to LAN)
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
  };
}
