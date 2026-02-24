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
  };
}
