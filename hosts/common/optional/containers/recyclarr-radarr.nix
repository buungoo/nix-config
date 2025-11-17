# Recyclarr sidecar for Radarr
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
  hostSpec.networking.containerNetworks.arr.containers.radarr = lib.mkDefault 5;

  containers.radarr =
    let
      net = lib.custom.mkContainerNetworkConfig config "arr" "radarr";
    in
    {
      autoStart = true;

      bindMounts = {
        "/var/lib/radarr" = {
          hostPath = "/mnt/storage/radarr";
          isReadOnly = false;
        };
        "/downloads" = {
          hostPath = "/mnt/storage/downloads";
          isReadOnly = false;
        };
        "/media/movies" = {
          hostPath = "/mnt/storage/media/movies";
          isReadOnly = false;
        };
        # Mount secrets into container
        "/run/secrets/recyclarr" = {
          hostPath = config.sops.secrets."recyclarr/radarr-api-key".path;
          isReadOnly = true;
        };
      };

      privateNetwork = true;
      hostBridge = net.bridge;
      localAddress = "${net.containerIP}/${net.cidr}";

      forwardPorts = [
        {
          hostPort = 7878;
          containerPort = 7878;
        }
      ];

      config = lib.mkMerge [
        (lib.custom.mkContainerBaseConfig net)
        {
          environment.systemPackages = with pkgs; [
            recyclarr
          ];

          services.radarr = {
            enable = true;
            openFirewall = true;
            dataDir = "/var/lib/radarr";
          };

          environment.etc."recyclarr/recyclarr.yml".text = ''
            radarr:
              movies:
                base_url: http://127.0.0.1:7878
                api_key: !secret radarr_api_key
                
                # Use TRaSH guides quality definitions
                quality_definition:
                  type: movie
                  
                # TRaSH guides quality profiles with 4K support
                quality_profiles:
                  - name: UHD Bluray + WEB
                    upgrade:
                      allowed: true
                      until_quality: Bluray-2160p
                      until_score: 10000
                    reset_unmatched_scores:
                      enabled: true
                      
                  - name: HD Bluray + WEB
                    upgrade:
                      allowed: true
                      until_quality: Bluray-1080p
                      until_score: 10000
                    reset_unmatched_scores:
                      enabled: true
                      
                # TRaSH guides custom formats for movies
                custom_formats:
                  - trash_ids:
                      # Movie Versions
                      - 9f6cbff8cfe4ebbc1bde14c7b7bec0de # IMAX Enhanced
                      - 09d9dd29a0fc958f9796e65c2a8864b4 # Open Matte
                      - 0f12c086e289cf966fa5948eac571f44 # Hybrid
                      - 570bc9ebecd92723d2d21500f4be314c # Remaster
                      - eca37840c13c6ef2dd0262b141a5482f # 4K Remaster
                      - e0c07d59beb37348e975a930d5e50319 # Criterion Collection
                      - 9d27d9d2181838f76dee150882bdc58c # Masters of Cinema
                      - db9b4c4b53d312a3ca5f1378f6440fc9 # Vinegar Syndrome
                      - 957d0f44b592285f26449575e8b1167e # Special Edition
                      - eecf3a857724171f968a66cb5719e152 # IMAX
                      - 9f6cbff8cfe4ebbc1bde14c7b7bec0de # IMAX Enhanced

                      # HQ Release Groups
                      - 4d74ac4c4db0b64bff6ce0cffb1909bd # UHD Bluray Tier 01
                      - a58f517a70193f8e578056642178419d # UHD Bluray Tier 02
                      - e71939fae578037e7aed3ee219bbe7c1 # UHD Bluray Tier 03
                      - c20f169ef63c5f40c2def54abaf4438e # WEB Tier 01
                      - 403816d65392c79236dcb6dd591aeda4 # WEB Tier 02
                      - af94e0fe497124d1f9ce732069ec8c3b # WEB Tier 03

                      # Unwanted
                      - 90a6f9a284dff5103f6346090e6280c8 # LQ
                      - dc98083864eb859e2208d2a9a6c7fb3c # x265 (HD)
                      - b8cd450cbfa689c0259a01d9e29ba3d6 # 3D
                      - 7357cf5161efbf8c4d5d0c30b4815ee2 # Obfuscated
                      - 5c44f52a8714fdd79bb4d98e2673be1f # Retags
                      - f537cf427b64c38c8e36298f657e4828 # Scene
                      - 0a3f082873eb454bde444150b70253cc # Extras
                      - bfd8eb01832d646a0a89c4deb46f8564 # Upscaled
                      - 9c38ebb7384dada637be8899efa68e6f # SDR
                    quality_profiles:
                      - name: UHD Bluray + WEB
                      - name: HD Bluray + WEB

                  # Optional: Prefer HDR
                  - trash_ids:
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
                    quality_profiles:
                      - name: UHD Bluray + WEB
                        score: 500 # Prefer HDR content
          '';

          systemd.services.recyclarr = {
            description = "Recyclarr - Configure Radarr with TRaSH guides";
            wants = [ "radarr.service" ];
            after = [ "radarr.service" ];

            serviceConfig = {
              Type = "oneshot";
              User = "radarr";
              Group = "radarr";
              WorkingDirectory = "/var/lib/radarr";

              ExecStartPre = pkgs.writeShellScript "recyclarr-setup-secrets" ''
                mkdir -p /var/lib/radarr/recyclarr/secrets
                echo "radarr_api_key: $(cat /run/secrets/recyclarr)" > /var/lib/radarr/recyclarr/secrets/secrets.yml
                chmod 600 /var/lib/radarr/recyclarr/secrets/secrets.yml
              '';

              ExecStart = "${pkgs.recyclarr}/bin/recyclarr sync --config /etc/recyclarr/recyclarr.yml --app-data /var/lib/radarr/recyclarr --secrets /var/lib/radarr/recyclarr/secrets/secrets.yml";

              ExecStartPost = "${pkgs.coreutils}/bin/rm -f /var/lib/radarr/recyclarr/secrets/secrets.yml";
            };
          };

          systemd.timers.recyclarr = {
            description = "Run recyclarr daily for Radarr";
            wantedBy = [ "timers.target" ];

            timerConfig = {
              OnCalendar = "daily";
              Persistent = true;
              RandomizedDelaySec = "1h";
            };
          };

          systemd.tmpfiles.rules = [
            "d /var/lib/radarr 0755 radarr radarr -"
            "d /var/lib/radarr/recyclarr 0755 radarr radarr -"
            "d /downloads 0755 radarr radarr -"
            "d /media/movies 0755 radarr radarr -"
          ];
        }
      ];
    };

  systemd = lib.mkMerge [
    (lib.custom.mkContainerSystemd "radarr" { })
    {
      tmpfiles.rules = [
        "d /mnt/storage/radarr 0755 root root -"
      ];
    }
  ];

  sops.secrets."recyclarr/radarr-api-key" = {
    sopsFile = ../../nix-secrets/sops/nas0.yaml;
    restartUnits = [ "container@radarr.service" ];
  };
}
