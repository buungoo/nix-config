{
  pkgs,
  hostSpec,
  lib,
  ...
}:
{
  home.packages = [
    (if hostSpec.isDarwin then pkgs.brewCasks.vivaldi else pkgs.vivaldi)
  ];
}
