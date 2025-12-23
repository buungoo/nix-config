# Samba file sharing service
# Configured to only allow SMB3 protocol for security
# 1. sudo mkdir -p /mnt/storage/<user>
# 2. sudo chown <user>:users /mnt/storage/<user>
# 3. sudo chmod 700 /mnt/storage/<user>
# 4. sudo smbpasswd -a <user>
{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Reuse the haproxy spec but we can't proxy QUIC via it as it would terminate TLS
  hostSpec.domains.files = {
    domain = "files.${config.hostSpec.domain}";
    public = false;
    backendHost = "127.0.0.1";
    backendPort = 445;
    backendSSL = false;
  };

  # Open UDP port 443 for SMB over QUIC
  networking.firewall.allowedUDPPorts = [ 443 ];

  services.samba = {
    enable = true;
    openFirewall = true; # Opens standard Samba TCP ports (139, 445)

    nmbd.enable = false;
    smbd.enable = true;
    winbindd.enable = false;

    settings = {
      global = {
        # Security settings
        security = "user";
        "invalid users" = [ "root" ];

        # Only allow SMB3 protocol
        "server min protocol" = "SMB3";
        "client min protocol" = "SMB3";

        # SMB over QUIC support (requires quic.ko kernel module and Linux >= 6.14)
        # Uses ACME certificates from files.domain for server identity
        # Requires client certificates from step-ca for mTLS
        # See: https://www.samba.org/samba/docs/current/man-html/smb.conf.5.html#SERVERSMBTRANSPORTS
        "server smb transports" = "+quic";
        "tls enabled" = true;
        "tls certfile" = "/var/lib/samba/tls/cert.pem";
        "tls keyfile" = "/var/lib/samba/tls/key.pem";
        "tls cafile" = "/mnt/storage/step-ca/.step/certs/ca_bundle.crt";
        "tls verify peer" = "ca_only"; # Require and verify client certificates

        # Signing is redundant as either QUIC or Wireguard will be used
        "server signing" = "disabled";
        "client signing" = "disabled";

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

      # Per-user home shares
      # Users connect to \\nas0\username to access /mnt/storage/username
      homes = {
        browseable = "no";
        "read only" = "no";
        "create mask" = "0644";
        "directory mask" = "0755";
        path = "/mnt/storage/%S";
        "valid users" = "%S";
      };
    };
  };

  # Create directory for Samba TLS certificates
  systemd.tmpfiles.rules = [
    "d /var/lib/samba/tls 0755 root root -"
  ];

  # Copy ACME certificates for Samba with correct ownership and permissions
  # Samba requires certificates to be owned by root with mode 0600 (CVE-2013-4476)
  systemd.services.samba-cert-copy = {
    description = "Copy ACME certificates for Samba with correct permissions";
    after = [ "acme-files.${config.hostSpec.domain}.service" ];
    wants = [ "acme-files.${config.hostSpec.domain}.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      if [ -f /var/lib/acme/files.${config.hostSpec.domain}/cert.pem ]; then
        cp /var/lib/acme/files.${config.hostSpec.domain}/cert.pem \
           /var/lib/samba/tls/cert.pem
        cp /var/lib/acme/files.${config.hostSpec.domain}/key.pem \
           /var/lib/samba/tls/key.pem
        cp /var/lib/acme/files.${config.hostSpec.domain}/chain.pem \
           /var/lib/samba/tls/chain.pem

        # Set correct ownership and permissions for Samba
        chown root:root /var/lib/samba/tls/*.pem
        chmod 0600 /var/lib/samba/tls/*.pem
      fi
    '';
  };

  # Ensure Samba waits for certificates and step-ca
  systemd.services.samba-smbd = {
    after = [
      "samba-cert-copy.service"
      "container@step-ca.service"
    ];
    wants = [
      "samba-cert-copy.service"
      "container@step-ca.service"
    ];
    # Override service type to simple instead of notify
    # Samba doesn't send systemd readiness notification, causing startup timeout
    serviceConfig = {
      Type = lib.mkForce "simple";
    };
  };

  # Create samba user and group
  users.users.samba = {
    isSystemUser = true;
    group = "samba";
    # Grant read access to ACME certificates and step-ca CA bundle
    extraGroups = [
      "acme"
      "ca-proxy"
    ];
  };
  users.groups.samba = { };
}
