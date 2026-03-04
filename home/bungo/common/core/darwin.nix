# Darwin-specific home-manager configuration
{
  config,
  lib,
  pkgs,
  ...
}:
{
  programs.nh = {
    enable = true;
    darwinFlake = "$HOME/.nixos/nix-config";
  };

  # Darwin-specific packages
  home.packages = with pkgs; [
  ];
}
