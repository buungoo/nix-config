{ pkgs, hostSpec, lib, ... }:
{
  # Orion browser (macOS only - WebKit based)
  home.packages = lib.optionals hostSpec.isDarwin [
    pkgs.brewCasks.orion
  ];
}
