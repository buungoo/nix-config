{
  pkgs,
  hostSpec,
  lib,
  ...
}:
{
  home.packages = [
    (
      if hostSpec.isDarwin then
        pkgs.brewCasks.steam.overrideAttrs (old: {
          src = pkgs.fetchurl {
            inherit (old.src) url;
            sha256 = "sha256-X1VnDJGv02A6ihDYKhedqQdE/KmPAQZkeJHudA6oS6M=";
          };
        })
      else
        pkgs.steam
    )
  ];
}
