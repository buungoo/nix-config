# Darwin-specific home-manager configuration
{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Darwin-specific home configuration

  # Darwin-specific packages
  home.packages = with pkgs; [
  ];
}
