{
  pkgs,
  hostSpec,
  lib,
  ...
}:
{
  # On Linux, Steam is provided by the NixOS module (programs.steam.enable)
  # which includes the wrapper for extraCompatPackages (Proton-GE, etc.)
  # Only install via home-manager on macOS
  home.packages = lib.optionals hostSpec.isDarwin [
    (pkgs.brewCasks.steam.overrideAttrs (old: {
      src = pkgs.fetchurl {
        inherit (old.src) url;
        sha256 = "sha256-X1VnDJGv02A6ihDYKhedqQdE/KmPAQZkeJHudA6oS6M=";
      };
    }))
  ];
}
