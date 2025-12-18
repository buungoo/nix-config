{ pkgs, hostSpec, lib, ... }:
{
  # AltServer via brew-nix (macOS only)
  home.packages = lib.optionals hostSpec.isDarwin [
    pkgs.brewCasks.altserver
  ];
}
