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
let
  platform = if hostSpec.isDarwin then "darwin" else "nixos";
in
{
  imports = [
    ./${platform}.nix
  ];
  home = {
    username = userName;
    homeDirectory = userVars.home;
    preferXdgDirectories = true;

    sessionVariables = {
      SOPS_AGE_KEY_FILE = "${userVars.home}/.config/sops/age/keys.txt";
    };
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

}
