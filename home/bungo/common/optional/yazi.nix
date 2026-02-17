{
  pkgs,
  ...
}:
let
  kanagawaFlavor = pkgs.runCommand "kanagawa-flavor" { } ''
    mkdir -p $out
    cp ${
      pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/dangooddd/kanagawa.yazi/main/flavor.toml";
        sha256 = "sha256-eIZTxvCrL+GzNcJIsHuyPL7OinsrWRx+bYVnBiCAw+Y=";
      }
    } $out/flavor.toml
  '';
in
{
  programs.yazi = {
    enable = true;
    flavors.kanagawa = kanagawaFlavor;
    plugins.full-border = pkgs.yaziPlugins.full-border;
    theme = {
      flavor = {
        dark = "kanagawa";
      };
    };
    initLua = ''
      require("full-border"):setup()
    '';
  };
}
