{
  pkgs,
  hostSpec,
  lib,
  ...
}:
{
  # home.packages = lib.optionals hostSpec.isDarwin [ pkgs.brewCasks.exiftool ];
  home.packages = lib.optionals hostSpec.isDarwin [
    pkgs.exiftool
  ];
}
