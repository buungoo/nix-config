# SMB over QUIC client module
# Configures Samba client with QUIC transport and mTLS client certificates
# for mounting remote Samba shares over the internet.
#
# Usage:
# 1. Add client cert/key to sops: samba-client/cert and samba-client/key
# 2. Enable: custom.services.sambaClient.enable = true
# 3. Mount: sudo mount -t cifs //files.bungos.xyz/media /mnt/nas-media -o credentials=/run/secrets/samba-client/credentials
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  cfg = config.custom.services.sambaClient;
  sopsFolder = builtins.toString inputs.nix-secrets + "/sops";
in
{
  options.custom.services.sambaClient = {
    enable = lib.mkEnableOption "SMB over QUIC client";

    serverHost = lib.mkOption {
      type = lib.types.str;
      default = "files.${config.hostSpec.domain}";
      description = "FQDN of the Samba server";
    };
  };

  config = lib.mkIf cfg.enable {
    # Packages
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

    # Client certificate secrets from sops
    sops.secrets = {
      "samba-client/cert" = {
        sopsFile = "${sopsFolder}/${config.hostSpec.hostName}.yaml";
        owner = "root";
        group = "root";
        mode = "0600";
      };
      "samba-client/key" = {
        sopsFile = "${sopsFolder}/${config.hostSpec.hostName}.yaml";
        owner = "root";
        group = "root";
        mode = "0600";
      };
    };

    # Minimal smb.conf for QUIC client with mTLS
    environment.etc."samba/smb.conf".text = ''
      [global]
        client min protocol = SMB3
        client smb transports = quic
        tls certfile = ${config.sops.secrets."samba-client/cert".path}
        tls keyfile = ${config.sops.secrets."samba-client/key".path}
        tls trust system cas = yes
        tls verify peer = ca_and_name
    '';
  };
}
