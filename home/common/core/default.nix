# Shared home-manager configuration for all users across all hosts
# This should contain ONLY bare necessities that every user needs
{
  config,
  lib,
  pkgs,
  userName,
  userVars,
  hostSpec,
  ...
}:
{
  home = {
    username = userName;
    homeDirectory = userVars.home;
    stateVersion = lib.mkDefault "23.05";
    preferXdgDirectories = true;
  };

  programs = {
    home-manager.enable = true;
  };

  # Enable nix flakes for user
  nix = {
    package = lib.mkDefault pkgs.nix;
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      warn-dirty = false;
    };
  };

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";
}
