# NixOS-specific user configuration for bungo
{
  config,
  lib,
  pkgs,
  ...
}:
{
  # NixOS-specific user settings
  users.users.bungo = {
    # Additional groups for NixOS
    extraGroups = [
      "audio"
      "video"
      "input"
      "systemd-journal"
    ];
  };
}
