# Unbound DNS resolver with DNS-over-TLS/QUIC
# Provides split-horizon DNS for local services
# Forwards queries to Quad9 over encrypted transport
{
  config,
  pkgs,
  lib,
  ...
}:

{
  # Disable systemd-resolved to avoid port 53 conflicts
  services.resolved.enable = false;

  # Enable Unbound DNS resolver
  services.unbound = {
    enable = true;

    settings = {
      server = {
        # Network interfaces
        interface = [
          "0.0.0.0"
          "::"
        ];
        port = 53;

        # Access control - allow local networks
        access-control = [
          "127.0.0.0/8 allow"
          "::1/128 allow"
          "${config.hostSpec.networking.localSubnet} allow"
          "10.0.0.0/8 allow" # Allow container networks
        ];

        # Performance tuning
        num-threads = 4;
        msg-cache-size = "128m";
        rrset-cache-size = "256m";
        cache-min-ttl = 300;
        cache-max-ttl = 86400;

        # Privacy and security
        hide-identity = true;
        hide-version = true;
        qname-minimisation = true;
        aggressive-nsec = true;
        use-caps-for-id = true;

        # Logging (disable after testing)
        verbosity = 1;
        log-queries = false;
        log-replies = false;
        log-servfail = true;

        # Prefetch popular queries before they expire
        prefetch = true;
        prefetch-key = true;

        # Local zones for split-horizon DNS
        # All queries for *.${domain} return local IP
        private-domain = [ ''"${config.hostSpec.domain}"'' ];

        # Define local data for split-horizon DNS
        local-zone = [ ''"${config.hostSpec.domain}." transparent'' ];

        local-data = [
          # Apex domain
          ''"${config.hostSpec.domain}. A ${config.hostSpec.networking.localIP}"''

          # Services
          ''"immich.${config.hostSpec.domain}. A ${config.hostSpec.networking.localIP}"''
          ''"auth.${config.hostSpec.domain}. A ${config.hostSpec.networking.localIP}"''
          ''"jellyfin.${config.hostSpec.domain}. A ${config.hostSpec.networking.localIP}"''
          ''"ca.${config.hostSpec.domain}. A ${config.hostSpec.networking.localIP}"''
        ];

        # Allow local data to be returned for private domains
        # but forward everything else (like TXT records for ACME)
        local-data-ptr = [ ''"${config.hostSpec.networking.localIP} ${config.hostSpec.domain}"'' ];
      };

      # DNS-over-TLS forwarding to Quad9
      forward-zone = [
        {
          name = ".";

          # Quad9 DNS-over-TLS endpoints
          forward-addr = [
            "9.9.9.9@853#dns.quad9.net"
            "149.112.112.112@853#dns.quad9.net"
            # IPv6
            "2620:fe::fe@853#dns.quad9.net"
            "2620:fe::9@853#dns.quad9.net"
          ];

          # Enable DNS-over-TLS
          forward-tls-upstream = true;

          # Fallback behavior
          forward-first = false; # Don't try regular DNS first
        }
      ];

      # Remote control (for unbound-control)
      remote-control = {
        control-enable = true;
        control-interface = "/run/unbound/unbound.ctl";
      };
    };
  };

  # Note: DNS-over-QUIC support in Unbound requires version 1.20.0+
  # As of NixOS 24.11, this should be available
  # If you want to enable DoQ, add these settings:
  #
  # services.unbound.settings.server = {
  #   # Experimental: DNS-over-QUIC
  #   # Requires Unbound 1.20.0+ with QUIC support compiled in
  #   # Uncomment if your Unbound version supports it:
  #   # quic-port = 853;
  #   # quic-size = "8m";
  # };

  # Open firewall for DNS
  networking.firewall.allowedTCPPorts = [ 53 ];
  networking.firewall.allowedUDPPorts = [ 53 ];

  # Set this host to use Unbound for DNS resolution
  networking.nameservers = [ "127.0.0.1" ];

  # Prevent dhcpcd from overwriting /etc/resolv.conf
  networking.resolvconf.enable = true;
  networking.resolvconf.useLocalResolver = true;
}
