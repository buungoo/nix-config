{ pkgs, hostSpec, lib, ... }:
{
  # Steam via brew-nix (macOS only)
  home.packages = lib.optionals hostSpec.isDarwin [
    (pkgs.brewCasks.steam.overrideAttrs (old: {
      src = pkgs.fetchurl {
        inherit (old.src) url;
        sha256 = "sha256-X1VnDJGv02A6ihDYKhedqQdE/KmPAQZkeJHudA6oS6M=";
      };
    }))
  ];
}
