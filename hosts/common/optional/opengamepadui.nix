{
  pkgs,
  config,
  ...
}:
{
  programs.opengamepadui = {
    enable = true;
    # inputplumber.enable = true;
    # powerstation.enable = true;
    gamescopeSession.enable = true;
  };
}
