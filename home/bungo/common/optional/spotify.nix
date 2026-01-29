{ pkgs, hostSpec, lib, ... }:
{
  # Spotify via brew-nix (macOS only)
  home.packages = lib.optionals hostSpec.isDarwin [
    (pkgs.brewCasks.spotify.overrideAttrs (old: {
      src = pkgs.fetchurl {
        inherit (old.src) url;
        sha256 = "sha256-i/+w9s/3ZQtLAEMVTcLaV69fhpKq2rT5+WoBzer0ahY=";
      };
    }))
  ];
}
