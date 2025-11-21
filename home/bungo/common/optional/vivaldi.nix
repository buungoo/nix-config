{ pkgs, hostSpec, lib, ... }:
{
  # Vivaldi browser
  # On Darwin: brew-nix package is broken (tarball extraction fails to find Vivaldi.app)
  # On Linux: use nixpkgs
  home.packages = [
    (if hostSpec.isDarwin
      then pkgs.brewCasks.vivaldi
      else pkgs.vivaldi)
  ];
}
