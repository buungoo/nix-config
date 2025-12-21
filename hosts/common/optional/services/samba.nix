# Samba file sharing service
# Configured to only allow SMB3 protocol for security
{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Open UDP port 443 for SMB over QUIC
  networking.firewall.allowedUDPPorts = [ 443 ];

  services.samba = {
    enable = true;
    openFirewall = true; # Opens standard Samba TCP ports (139, 445)

    # Enable/disable daemons
    nmbd.enable = false;
    smbd.enable = true;
    winbindd.enable = false;

    settings = {
      global = {
        # Security settings
        security = "user";
        "invalid users" = [ "root" ];

        # Only allow SMB3 protocol (disable SMB1 and SMB2)
        "server min protocol" = "SMB3";
        "client min protocol" = "SMB3";

        # SMB over QUIC support (requires quic.ko kernel module and Linux >= 6.14)
        # Adds QUIC transport on UDP port 443 alongside default TCP and NBT transports
        # Auto-generates self-signed TLS certificate if tls certfile/keyfile don't exist
        "server smb transports" = "+quic";

        # Additional security settings
        "server signing" = "mandatory";
        "client signing" = "mandatory";

        # Server identity
        workgroup = "WORKGROUP";
        "server string" = config.hostSpec.hostAlias;
        "netbios name" = config.hostSpec.hostName;

        # Disable printer sharing
        "load printers" = false;
        printing = "bsd";
        "printcap name" = "/dev/null";
        "disable spoolss" = true;

        # Logging
        "log file" = "/var/log/samba/%m.log";
        "log level" = "1";
      };

      # Example shares - customize as needed
      # storage = {
      #   path = "/mnt/storage";
      #   browseable = "yes";
      #   "read only" = "no";
      #   "guest ok" = "no";
      #   "create mask" = "0644";
      #   "directory mask" = "0755";
      # };
    };
  };
}
