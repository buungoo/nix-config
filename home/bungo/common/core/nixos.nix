# NixOS-specific home-manager configuration
{
  config,
  lib,
  pkgs,
  ...
}:
{
  programs.nh = {
    enable = true;
    osFlake = "$HOME/.nixos/nix-config";
  };

  # Linux-specific packages
  home.packages = with pkgs; [
  ];
}
