{
  lib,
  pkgs,
  osconfig,
  ...
}:

# Settings for bungo on macbook
{
  imports = lib.flatten [
    (map lib.custom.relativeToRoot [
      "home/bungo/common/core"
      "home/bungo/common/optional/ghostty.nix"
      "home/bungo/common/optional/orion.nix"
      "home/bungo/common/optional/brave.nix"
      "home/bungo/common/optional/yabai.nix"
      "home/bungo/common/optional/skhd.nix"
      "home/bungo/common/optional/raycast.nix"
      "home/bungo/common/optional/discord.nix"
      "home/bungo/common/optional/commander-one.nix"
      "home/bungo/common/optional/spotify.nix"
      "home/bungo/common/optional/steam.nix"
      "home/bungo/common/optional/whisky.nix"
      "home/bungo/common/optional/altserver.nix"
      "home/common/optional/sops.nix"
    ])
  ];

  home = {
    stateVersion = "25.05";

    packages = with pkgs; [
      # Add macbook-specific packages here
    ];
  };
}
