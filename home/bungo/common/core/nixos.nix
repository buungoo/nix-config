# NixOS-specific home-manager configuration
{
  config,
  lib,
  pkgs,
  ...
}:
{
  # NixOS-specific home configuration

  # nh configuration for NixOS
  programs.nh.osFlake = "$HOME/.nixos/nix-config";

  # Linux-specific packages
  home.packages = with pkgs; [
  ];
}
