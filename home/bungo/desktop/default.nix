{
  lib,
  pkgs,
  osConfig,
  inputs,
  config,
  ...
}:
let
  sopsFolder = (builtins.toString inputs.nix-secrets) + "/sops";
  homeDirectory = config.home.homeDirectory;
in
# Settings for bungo on desktop
{
  imports = lib.flatten [
    (map lib.custom.relativeToRoot [
      "home/bungo/common/core"
      "home/common/optional/sops.nix"

      "home/bungo/common/optional/ghostty.nix"
      "home/bungo/common/optional/spotify.nix"
      "home/bungo/common/optional/vivaldi.nix"
      "home/bungo/common/optional/discord.nix"
      "home/bungo/common/optional/steam.nix"
      "home/bungo/common/optional/hyprland.nix"
      "home/bungo/common/optional/neowall.nix"
      "home/bungo/common/optional/noctalia.nix"
      "home/bungo/common/optional/oxicord.nix"
      "home/bungo/common/optional/freetube.nix"
      "home/bungo/common/optional/vacuumtube.nix"
      "home/bungo/common/optional/orcaslicer.nix"
      "home/bungo/common/optional/dolphin.nix"

      "home/bungo/nixos/common/optional/walker.nix"
      # "home/bungo/nixos/common/optional/freecad.nix" # Takes ages to compile!
    ])
  ];

  # Deploy SSH private key from secrets
  sops.secrets."ssh/bungo/private_key" = {
    sopsFile = "${sopsFolder}/${osConfig.hostSpec.hostName}.yaml";
    path = "${homeDirectory}/.ssh/id_ed25519";
  };

  home = {
    stateVersion = "25.11";
  };
}
