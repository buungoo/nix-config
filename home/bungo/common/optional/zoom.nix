{
  pkgs,
  ...
}:
{
  home.packages = [
    pkgs.brewCasks.zoom
  ];
}
