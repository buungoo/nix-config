# NixOS-specific home-manager configuration
{
  config,
  lib,
  pkgs,
  ...
}:
{
  # NixOS-specific home configuration

  # Linux-specific packages
  home.packages = with pkgs; [
  ];
}
