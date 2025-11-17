# NixOS module for step-ca enrollment service
{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.services.step-ca-enroll;
in
{
  options.services.step-ca-enroll = {
    enable = mkEnableOption "step-ca OIDC enrollment service for client certificates";

    kanidmUrl = mkOption {
      type = types.str;
      description = "Kanidm instance URL";
      example = "https://auth.example.com";
    };

    oidcClientId = mkOption {
      type = types.str;
      default = "step-ca-enroll";
      description = "OIDC client ID";
    };

    redirectUrl = mkOption {
      type = types.str;
      description = "OAuth2 redirect URL";
      example = "https://ca.example.com/callback";
    };

    stepCaUrl = mkOption {
      type = types.str;
      description = "step-ca API URL";
      example = "https://10.0.9.2:9443";
    };

    bindAddr = mkOption {
      type = types.str;
      default = "127.0.0.1:3000";
      description = "Address to bind the HTTP server";
    };

    oidcClientSecretFile = mkOption {
      type = types.path;
      description = "Path to file containing OIDC client secret";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.step-ca-enroll = {
      description = "step-ca OIDC enrollment service for client certificates";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        KANIDM_URL = cfg.kanidmUrl;
        OIDC_CLIENT_ID = cfg.oidcClientId;
        REDIRECT_URL = cfg.redirectUrl;
        STEP_CA_URL = cfg.stepCaUrl;
        BIND_ADDR = cfg.bindAddr;
      };

      serviceConfig = {
        Type = "simple";
        Restart = "on-failure";
        RestartSec = "10s";

        # Security hardening
        DynamicUser = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
        ];
        RestrictNamespaces = true;
        LockPersonality = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;

        # Load OIDC client secret from sops
        LoadCredential = [
          "oidc-client-secret:${cfg.oidcClientSecretFile}"
        ];
      };

      # Set OIDC_CLIENT_SECRET environment variable from credential
      script = ''
        export OIDC_CLIENT_SECRET=$(cat $CREDENTIALS_DIRECTORY/oidc-client-secret)
        exec ${pkgs.step-ca-enroll}/bin/step-ca-enroll
      '';
    };
  };
}
