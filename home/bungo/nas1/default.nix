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
# Settings for bungo on nas1
{
  imports = lib.flatten [
    (map lib.custom.relativeToRoot [
      "home/bungo/common/core"
      "home/common/optional/sops.nix"
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
