# Recyclarr sidecar for Sonarr
{
  config,
  pkgs,
  lib,
  ...
}:

{
  imports = [
    (./networking.nix)
  ];

  hostSpec.networking.containerNetworks.arr.bridge = lib.mkDefault "arr-bridge";
  hostSpec.networking.containerNetworks.arr.subnet = lib.mkDefault "10.0.1.0/24";
  hostSpec.networking.containerNetworks.arr.gateway = lib.mkDefault "10.0.1.1";
  hostSpec.networking.containerNetworks.arr.containers.sonarr = lib.mkDefault 4;

  containers.sonarr =
    let
      net = lib.custom.mkContainerNetworkConfig config "arr" "sonarr";
    in
    {
      autoStart = true;

      bindMounts = {
        "/var/lib/sonarr" = {
          hostPath = "/mnt/storage/sonarr";
          isReadOnly = false;
        };
        "/downloads" = {
          hostPath = "/mnt/storage/downloads";
          isReadOnly = false;
        };
        "/media/tvshows" = {
          hostPath = "/mnt/storage/media/tvshows";
          isReadOnly = false;
        };
        # Mount secrets into container
        "/run/secrets/recyclarr" = {
          hostPath = config.sops.secrets."recyclarr/sonarr-api-key".path;
          isReadOnly = true;
        };
      };

      privateNetwork = true;
      hostBridge = net.bridge;
      localAddress = "${net.containerIP}/${net.cidr}";

      forwardPorts = [
        {
          hostPort = 8989;
          containerPort = 8989;
        }
      ];

      config = lib.mkMerge [
        (lib.custom.mkContainerBaseConfig net)
        {
          environment.systemPackages = with pkgs; [
            recyclarr
          ];

          services.sonarr = {
            enable = true;
            openFirewall = true;
            dataDir = "/var/lib/sonarr";
          };

          environment.etc."recyclarr/recyclarr.yml".text = ''
            sonarr:
              series:
              base_url: http://127.0.0.1:8989
                api_key: !secret sonarr_api_key
                
                # Use TRaSH guides quality definitions
                quality_definition:
                  type: series
                  
                # TRaSH guides quality profiles with 4K support
                quality_profiles:
                  - name: WEB-2160p
                    upgrade:
                      allowed: true
                      until_quality: WEB 2160p
                      until_score: 10000
                    reset_unmatched_scores:
                      enabled: true
                    
                  - name: WEB-1080p
                    upgrade:
                      allowed: true
                      until_quality: WEB 1080p
                      until_score: 10000
                    reset_unmatched_scores:
                      enabled: true
                      
                # TRaSH guides custom formats
                custom_formats:
                  - trash_ids:
                      # HDR Formats
                      - e23edd2482476e595fb990b12e7c609c # DV HDR10  
                      - 58d6a88f13e2db7f5059c41047876f00 # DV
                      - 55d53828b9d81cbe20b02efd00aa0efd # DV HLG  
                      - a3e19f8f627608af0211acd02bf89735 # DV SDR  
                      - b974a6cd08c1066250f1f177d7aa1225 # HDR10+
                      - dfb86d5941bc9075d6af23b09c2aeecd # HDR10
                      - e61e28db95d22bedcadf030b8f156d96 # HDR
                      - 2a4d9069cc1fe3242ff9bdaebed239bb # HDR (undefined)
                      - 08d6d8834ad9ec87b1dc7ec8148e7a1f # PQ
                      - 9364dd386c9b4a1100dde8264690add7 # HLG

                      # Unwanted
                      - 85c61753df5da1fb2aab6f2a47426b09 # BR-DISK
                      - 9c11cd3f07101cdba90a2d81cf0e56b4 # LQ
                      - 47435ece6b99a0b477caf360e79ba0bb # x265 (HD)
                      - fbcb31d8dabd2a319072b84fc0b7249c # Repacks/Propers
                      - 205125755c411c3b8622ca3175d27b37 # HDR10Plus Boost
                      - 1af239278386be2919e1bcee0bde047e # HDR10Plus Boost
                      - 2016d1676f5ee13a5b7257ff86ac9a93 # SDR
                      - 32b367365729d530ca1c124a0b180c64 # Bad Dual Groups
                      - 82d40da2bc6923f41e14394075dd4b03 # No-RlsGroup
                      - e1a997ddb54e3ecbfe06341ad323c458 # Obfuscated
                      - 06d66ab109d4d2eddb2794d21526d140 # Retags
                      - 1b3994c551cbb92a2c781af061f4ab44 # Scene
                    quality_profiles:
                      - name: WEB-2160p
                      - name: WEB-1080p
          '';

          systemd.services.recyclarr = {
            description = "Recyclarr - Configure Sonarr with TRaSH guides";
            wants = [ "sonarr.service" ];
            after = [ "sonarr.service" ];

            serviceConfig = {
              Type = "oneshot";
              User = "sonarr";
              Group = "sonarr";
              WorkingDirectory = "/var/lib/sonarr";

              ExecStartPre = pkgs.writeShellScript "recyclarr-setup-secrets" ''
                mkdir -p /var/lib/sonarr/recyclarr/secrets
                echo "sonarr_api_key: $(cat /run/secrets/recyclarr)" > /var/lib/sonarr/recyclarr/secrets/secrets.yml
                chmod 600 /var/lib/sonarr/recyclarr/secrets/secrets.yml
              '';

              ExecStart = "${pkgs.recyclarr}/bin/recyclarr sync --config /etc/recyclarr/recyclarr.yml --app-data /var/lib/sonarr/recyclarr --secrets /var/lib/sonarr/recyclarr/secrets/secrets.yml";

              ExecStartPost = "${pkgs.coreutils}/bin/rm -f /var/lib/sonarr/recyclarr/secrets/secrets.yml";
            };
          };

          systemd.timers.recyclarr = {
            description = "Run recyclarr daily for Sonarr";
            wantedBy = [ "timers.target" ];

            timerConfig = {
              OnCalendar = "daily";
              Persistent = true;
              RandomizedDelaySec = "1h";
            };
          };

          systemd.tmpfiles.rules = [
            "d /var/lib/sonarr 0755 sonarr sonarr -"
            "d /var/lib/sonarr/recyclarr 0755 sonarr sonarr -"
            "d /downloads 0755 sonarr sonarr -"
            "d /media/tvshows 0755 sonarr sonarr -"
          ];
        }
      ];
    };

  systemd = lib.mkMerge [
    (lib.custom.mkContainerSystemd "sonarr" { })
    {
      tmpfiles.rules = [
        "d /mnt/storage/sonarr 0755 root root -"
      ];
    }
  ];

  sops.secrets."recyclarr/sonarr-api-key" = {
    sopsFile = ../../nix-secrets/sops/nas0.yaml;
    restartUnits = [ "container@sonarr.service" ];
  };
}
