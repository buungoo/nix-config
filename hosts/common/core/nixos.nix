# NixOS-specific core configuration
{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Boot loader
  boot.loader.systemd-boot.enable = true;

  # Console and keyboard layout (NixOS-specific)
  console.keyMap = lib.mkDefault "sv-latin1";
  services.xserver.xkb = {
    layout = lib.mkDefault "se";
    variant = lib.mkDefault "nodeadkeys";
  };
}
