{
  pkgs,
  ...
}:
{
  home.packages = [
    pkgs.brewCasks.soduto
  ];
  # TODO: setup kdeconnect for other hosts later
  # home.services.kdeconnect.enable = true;
}
