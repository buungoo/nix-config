{ pkgs, hostSpec, lib, ... }:
{
  # Spotify via brew-nix (macOS only)
  home.packages = lib.optionals hostSpec.isDarwin [
    (pkgs.brewCasks.spotify.overrideAttrs (old: {
      src = pkgs.fetchurl {
        inherit (old.src) url;
        sha256 = "sha256-/rrThZOpjzaHPX1raDe5X8PqtJeTI4GDS5sXSfthXTQ=";
      };
    }))
  ];
}
