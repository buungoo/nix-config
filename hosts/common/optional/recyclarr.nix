# Recyclarr
{
  config,
  pkgs,
  lib,
  ...
}:

{
  services.recyclarr = {
    enable = true;

    configuration = {
      sonarr = {
        series = {
          base_url = "http://10.0.1.4:8989";
          api_key = {
            _secret = "/run/credentials/recyclarr.service/sonarr-api-key";
          };

          quality_definition = {
            type = "series";
          };

          media_naming = {
            series = "default";
            season = "default";
            episodes = {
              rename = true;
              standard = "default";
              daily = "default";
              anime = "default";
            };
          };

          quality_profiles = [
            {
              name = "WEB-2160p";
              reset_unmatched_scores.enabled = true;
              upgrade = {
                allowed = true;
                until_quality = "WEB 2160p";
                until_score = 10000;
              };
              qualities = [
                {
                  name = "WEB 2160p";
                  qualities = [
                    "WEBDL-2160p"
                    "WEBRip-2160p"
                  ];
                }
                {
                  name = "WEB 1080p";
                  qualities = [
                    "WEBDL-1080p"
                    "WEBRip-1080p"
                  ];
                }
                {
                  name = "WEB 720p";
                  qualities = [
                    "WEBDL-720p"
                    "WEBRip-720p"
                  ];
                }
              ];
            }
            {
              name = "WEB-1080p";
              reset_unmatched_scores.enabled = true;
              upgrade = {
                allowed = true;
                until_quality = "WEB 1080p";
                until_score = 10000;
              };
              qualities = [
                {
                  name = "WEB 1080p";
                  qualities = [
                    "WEBDL-1080p"
                    "WEBRip-1080p"
                  ];
                }
                {
                  name = "WEB 720p";
                  qualities = [
                    "WEBDL-720p"
                    "WEBRip-720p"
                  ];
                }
                { name = "HDTV-1080p"; }
                { name = "HDTV-720p"; }
              ];
            }
          ];

          custom_formats = [
            {
              trash_ids = [
                # HDR Formats
                "e23edd2482476e595fb990b12e7c609c" # DV HDR10
                "58d6a88f13e2db7f5059c41047876f00" # DV
                "55d53828b9d81cbe20b02efd00aa0efd" # DV HLG
                "a3e19f8f627608af0211acd02bf89735" # DV SDR
                "b974a6cd08c1066250f1f177d7aa1225" # HDR10+
                "dfb86d5941bc9075d6af23b09c2aeecd" # HDR10
                "e61e28db95d22bedcadf030b8f156d96" # HDR
                "2a4d9069cc1fe3242ff9bdaebed239bb" # HDR (undefined)
                "08d6d8834ad9ec87b1dc7ec8148e7a1f" # PQ
                "9364dd386c9b4a1100dde8264690add7" # HLG

                # Unwanted
                "85c61753df5da1fb2aab6f2a47426b09" # BR-DISK
                "9c11cd3f07101cdba90a2d81cf0e56b4" # LQ
                "fbcb31d8dabd2a319072b84fc0b7249c" # Repacks/Propers
                "205125755c411c3b8622ca3175d27b37" # HDR10Plus Boost
                "2016d1676f5ee13a5b7257ff86ac9a93" # SDR
                "32b367365729d530ca1c124a0b180c64" # Bad Dual Groups
                "82d40da2bc6923f41e14394075dd4b03" # No-RlsGroup
                "e1a997ddb54e3ecbfe06341ad323c458" # Obfuscated
                "06d66ab109d4d2eddb2794d21526d140" # Retags
                "1b3994c551cbb92a2c781af061f4ab44" # Scene

                # Size Management
                "8e9a4f7eea6f3f4a7d82b7f324a0c3d9" # Excessive Size
                "5a6bcc2c0d24b05f5c3b9b5f5b5a5b5a" # High Bitrate 2160p
              ];
              quality_profiles = [
                { name = "WEB-2160p"; }
                { name = "WEB-1080p"; }
              ];
            }
          ];
        };
      };

      radarr = {
        movies = {
          base_url = "http://10.0.1.5:7878";
          api_key = {
            _secret = "/run/credentials/recyclarr.service/radarr-api-key";
          };

          quality_definition = {
            type = "movie";
          };

          media_naming = {
            folder = "default";
            movie = {
              rename = true;
              standard = "default";
            };
          };

          quality_profiles = [
            {
              name = "UHD WEB Only";
              reset_unmatched_scores.enabled = true;
              upgrade = {
                allowed = true;
                until_quality = "WEB 2160p";
                until_score = 10000;
              };
              qualities = [
                {
                  name = "WEB 2160p";
                  qualities = [
                    "WEBDL-2160p"
                    "WEBRip-2160p"
                  ];
                }
                {
                  name = "WEB 1080p";
                  qualities = [
                    "WEBDL-1080p"
                    "WEBRip-1080p"
                  ];
                }
                {
                  name = "WEB 720p";
                  qualities = [
                    "WEBDL-720p"
                    "WEBRip-720p"
                  ];
                }
              ];
            }
            {
              name = "HD WEB Only";
              reset_unmatched_scores.enabled = true;
              upgrade = {
                allowed = true;
                until_quality = "WEB 1080p";
                until_score = 10000;
              };
              qualities = [
                {
                  name = "WEB 1080p";
                  qualities = [
                    "WEBDL-1080p"
                    "WEBRip-1080p"
                  ];
                }
                {
                  name = "WEB 720p";
                  qualities = [
                    "WEBDL-720p"
                    "WEBRip-720p"
                  ];
                }
                { name = "HDTV-1080p"; }
                { name = "HDTV-720p"; }
              ];
            }
          ];

          custom_formats = [
            {
              trash_ids = [
                # Movie Versions
                "9f6cbff8cfe4ebbc1bde14c7b7bec0de" # IMAX Enhanced
                "09d9dd29a0fc958f9796e65c2a8864b4" # Open Matte
                "0f12c086e289cf966fa5948eac571f44" # Hybrid
                "570bc9ebecd92723d2d21500f4be314c" # Remaster
                "eca37840c13c6ef2dd0262b141a5482f" # 4K Remaster
                "e0c07d59beb37348e975a930d5e50319" # Criterion Collection
                "9d27d9d2181838f76dee150882bdc58c" # Masters of Cinema
                "db9b4c4b53d312a3ca5f1378f6440fc9" # Vinegar Syndrome
                "957d0f44b592285f26449575e8b1167e" # Special Edition
                "eecf3a857724171f968a66cb5719e152" # IMAX

                # HQ Release Groups
                "c20f169ef63c5f40c2def54abaf4438e" # WEB Tier 01
                "403816d65392c79236dcb6dd591aeda4" # WEB Tier 02
                "af94e0fe497124d1f9ce732069ec8c3b" # WEB Tier 03

                # Unwanted
                "90a6f9a284dff5103f6346090e6280c8" # LQ
                "b8cd450cbfa689c0259a01d9e29ba3d6" # 3D
                "7357cf5161efbf8c4d5d0c30b4815ee2" # Obfuscated
                "5c44f52a8714fdd79bb4d98e2673be1f" # Retags
                "f537cf427b64c38c8e36298f657e4828" # Scene
                "0a3f082873eb454bde444150b70253cc" # Extras
                "bfd8eb01832d646a0a89c4deb46f8564" # Upscaled
                "9c38ebb7384dada637be8899efa68e6f" # SDR

                # Size Management
                "8e9a4f7eea6f3f4a7d82b7f324a0c3d9" # Excessive Size
                "5a6bcc2c0d24b05f5c3b9b5f5b5a5b5a" # High Bitrate 2160p
              ];
              quality_profiles = [
                { name = "UHD WEB Only"; }
                { name = "HD WEB Only"; }
              ];
            }
            {
              trash_ids = [
                "e23edd2482476e595fb990b12e7c609c" # DV HDR10
                "58d6a88f13e2db7f5059c41047876f00" # DV
                "55d53828b9d81cbe20b02efd00aa0efd" # DV HLG
                "a3e19f8f627608af0211acd02bf89735" # DV SDR
                "b974a6cd08c1066250f1f177d7aa1225" # HDR10+
                "dfb86d5941bc9075d6af23b09c2aeecd" # HDR10
                "e61e28db95d22bedcadf030b8f156d96" # HDR
                "2a4d9069cc1fe3242ff9bdaebed239bb" # HDR (undefined)
                "08d6d8834ad9ec87b1dc7ec8148e7a1f" # PQ
                "9364dd386c9b4a1100dde8264690add7" # HLG
              ];
              quality_profiles = [
                {
                  name = "UHD WEB Only";
                  score = 500;
                }
              ];
            }
          ];
        };
      };
    };
  };

  systemd.services.recyclarr = {
    serviceConfig = {
      LoadCredential = [
        "sonarr-api-key:${config.sops.secrets."recyclarr/sonarr-api-key".path}"
        "radarr-api-key:${config.sops.secrets."recyclarr/radarr-api-key".path}"
      ];
    };
  };
}
