# SMB over QUIC client module
# Configures Samba client with QUIC transport and mTLS client certificates
# for mounting remote Samba shares over the internet.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.custom.services.sambaClient;
in
{
  options.custom.services.sambaClient = {
    enable = lib.mkEnableOption "SMB over QUIC client";

    serverHost = lib.mkOption {
      type = lib.types.str;
      default = "files.${config.hostSpec.domain}";
      description = "FQDN of the Samba server";
    };

    tlsCertFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to the client TLS certificate (PEM)";
    };

    tlsKeyFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to the client TLS private key (PEM)";
    };

    credentials = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          username = lib.mkOption {
            type = lib.types.str;
            description = "SMB username for authentication";
          };
          passwordFile = lib.mkOption {
            type = lib.types.path;
            description = "Path to file containing the SMB password (e.g. a sops secret path)";
          };
        };
      });
      default = { };
      description = ''
        Named SMB credential sets. Each generates a credentials file
        at /etc/samba/credentials/<name> for use with mount.cifs.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.samba
      pkgs.cifs-utils
    ];

    # QUIC kernel module
    boot.kernelModules = [ "quic" ];
    boot.extraModulePackages = [
      (pkgs.callPackage ../../pkgs/common/quic-kernel-module {
        kernel = config.boot.kernelPackages.kernel;
      })
    ];

    # Minimal smb.conf for QUIC client with mTLS
    environment.etc."samba/smb.conf".text = ''
      [global]
        client min protocol = SMB3
        client smb transports = quic
        tls certfile = ${cfg.tlsCertFile}
        tls keyfile = ${cfg.tlsKeyFile}
        tls trust system cas = yes
        tls verify peer = ca_and_name
    '';

    # Credential files for mount.cifs
    systemd.tmpfiles.rules = lib.optionals (cfg.credentials != { }) [
      "d /etc/samba/credentials 0700 root root -"
    ];

    systemd.services = lib.mapAttrs' (name: cred:
      lib.nameValuePair "smb-credentials-${name}" {
        description = "Generate SMB credentials file for ${name}";
        after = [ "sops-nix.service" ];
        wants = [ "sops-nix.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          install -m 0600 /dev/null '/etc/samba/credentials/${name}'
          {
            printf '%s\n' 'username=${cred.username}'
            printf 'password=%s\n' "$(cat '${cred.passwordFile}')"
          } > '/etc/samba/credentials/${name}'
        '';
      }
    ) cfg.credentials;
  };
}
