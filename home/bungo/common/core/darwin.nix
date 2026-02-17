# Darwin-specific home-manager configuration
{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Darwin-specific home configuration
  programs.nh.darwinFlake = "$HOME/.nixos/nix-config";

  # Darwin-specific packages
  home.packages = with pkgs; [
  ];
}
