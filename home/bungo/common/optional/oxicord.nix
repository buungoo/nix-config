{ inputs, pkgs, config, ... }:
{
  home.packages = [
    inputs.oxicord.packages.${pkgs.system}.default
    pkgs.discordo
  ];

  # TODO: add to sops secrets
  # sops.secrets."oxicord/token" = { };
  # home.sessionVariablesExtra = ''
  #   export OXICORD_TOKEN="$(cat ${config.sops.secrets."oxicord/token".path})"
  # '';
}
