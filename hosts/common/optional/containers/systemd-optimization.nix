{
  config,
  lib,
  pkgs,
  ...
}:
{
  systemd.services =
    # Auto-generate service optimizations for all containers
    (lib.mapAttrs' (
      name: _:
      lib.nameValuePair "container@${name}" {
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
      }
    ) config.containers)
    //
    # Manual dependency overrides for containers that depend on others
    {
      "container@jellyseer" = {
        wants = [
          "network-online.target"
          "container@sonarr.service"
          "container@radarr.service"
        ];
        after = [
          "network-online.target"
          "container@sonarr.service"
          "container@radarr.service"
        ];
      };

      "container@bazarr" = {
        wants = [
          "network-online.target"
          "container@sonarr.service"
          "container@radarr.service"
        ];
        after = [
          "network-online.target"
          "container@sonarr.service"
          "container@radarr.service"
        ];
      };
    };

  # System-wide optimizations
  systemd.settings.Manager = {
    DefaultTimeoutStartSec = "15s";
    DefaultTimeoutStopSec = "10s";
  };
}
