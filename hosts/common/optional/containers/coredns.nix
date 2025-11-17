# CoreDNS container for split-horizon DNS
# Responds to *.<domain>.<TLD> queries with LAN IP
# Forwards all other queries to upstream DNS
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

{
  imports = [
    (./networking.nix)
  ];

  # CoreDNS network configuration
  hostSpec.networking.containerNetworks.dns.bridge = lib.mkDefault "dns-bridge";
  hostSpec.networking.containerNetworks.dns.subnet = lib.mkDefault "10.0.53.0/24";
  hostSpec.networking.containerNetworks.dns.gateway = lib.mkDefault "10.0.53.1";
  hostSpec.networking.containerNetworks.dns.containers.coredns = lib.mkDefault 2;

  # Override host DNS servers to use CoreDNS container
  hostSpec.networking.dnsServers = lib.mkForce [ "10.0.53.2" ];

  containers.coredns =
    let
      net = lib.custom.mkContainerNetworkConfig config "dns" "coredns";

      # Corefile configuration
      corefileContent = ''
        # Split-horizon DNS for ${config.hostSpec.domain} domain
        ${config.hostSpec.domain} {
          # Log all queries for this domain
          log

          # Errors
          errors

          # Health check endpoint
          health :8080

          # Use hosts plugin for A records (not authoritative)
          hosts /etc/coredns/${config.hostSpec.domain}.hosts {
            fallthrough
          }

          # Forward everything else (including TXT records) to Cloudflare
          forward . 1.1.1.1 8.8.8.8

          # Cache for 30 seconds
          cache 30
        }

        # Forward all other queries to upstream DNS
        . {
          # Forward to Cloudflare and Google DNS
          forward . 1.1.1.1 8.8.8.8

          # Cache for 1 hour
          cache 3600

          # Log queries
          log

          # Errors
          errors
        }
      '';

      # Hosts file for ${config.hostSpec.domain} split-horizon DNS
      # Simple /etc/hosts format - only A records
      # TXT records and other types will be forwarded to Cloudflare
      hostsfileContent = ''
        # Apex domain
        ${config.hostSpec.networking.localIP} ${config.hostSpec.domain}

        # Services
        ${config.hostSpec.networking.localIP} immich.${config.hostSpec.domain}
        ${config.hostSpec.networking.localIP} auth.${config.hostSpec.domain}
        ${config.hostSpec.networking.localIP} jellyfin.${config.hostSpec.domain}
        ${config.hostSpec.networking.localIP} ca.${config.hostSpec.domain}
      '';
    in
    {
      autoStart = true;

      bindMounts = {
        # CoreDNS configuration
        "/etc/coredns/Corefile" = {
          hostPath = "${pkgs.writeText "Corefile" corefileContent}";
          isReadOnly = true;
        };
        "/etc/coredns/${config.hostSpec.domain}.hosts" = {
          hostPath = "${pkgs.writeText "${config.hostSpec.domain}.hosts" hostsfileContent}";
          isReadOnly = true;
        };
      };

      privateNetwork = true;
      hostBridge = net.bridge;
      localAddress = "${net.containerIP}/${net.cidr}";

      # Expose DNS on host interface (both TCP and UDP port 53)
      forwardPorts = [
        {
          hostPort = 53;
          containerPort = 53;
        }
      ];

      config = lib.mkMerge [
        (lib.custom.mkContainerBaseConfig net)
        {
          # Install CoreDNS
          environment.systemPackages = with pkgs; [
            coredns
          ];

          # CoreDNS service
          systemd.services.coredns = {
            enable = true;
            description = "CoreDNS DNS server";
            after = [ "network.target" ];
            wantedBy = [ "multi-user.target" ];

            serviceConfig = {
              Type = "simple";
              User = "coredns";
              Group = "coredns";
              ExecStart = "${pkgs.coredns}/bin/coredns -conf /etc/coredns/Corefile";
              Restart = "on-failure";
              RestartSec = "5s";

              # Security hardening
              NoNewPrivileges = true;
              PrivateTmp = true;
              ProtectSystem = "strict";
              ProtectHome = true;
              ReadWritePaths = [ ];

              # Allow binding to port 53
              AmbientCapabilities = "CAP_NET_BIND_SERVICE";
              CapabilityBoundingSet = "CAP_NET_BIND_SERVICE";
            };
          };

          # Create coredns user
          users.users.coredns = {
            isSystemUser = true;
            group = "coredns";
          };
          users.groups.coredns = { };

          # Open DNS ports
          networking.firewall.allowedTCPPorts = [
            53
            8080
          ];
          networking.firewall.allowedUDPPorts = [ 53 ];
        }
      ];
    };

  # Host systemd configuration
  systemd = lib.mkMerge [
    (lib.custom.mkContainerSystemd "coredns" { })
  ];

  # Keep systemd-resolved enabled, but configure it to use CoreDNS
  # This is simpler than trying to make resolvconf work with systemd-networkd
  services.resolved = {
    enable = true;
    fallbackDns = [ "10.0.53.2" ]; # Use CoreDNS container as fallback
  };

  # Override to use CoreDNS directly (systemd-networkd already configured via hostSpec.networking.dnsServers)
  networking.resolvconf.useLocalResolver = false;

  # Note: UDP port 53 forwarding is handled automatically by networking.nix
  # which generates both TCP and UDP DNAT rules for port 53
}
