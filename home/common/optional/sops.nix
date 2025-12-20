# home level sops configuration
{
  inputs,
  config,
  lib,
  ...
}:
let
  sopsFolder = (builtins.toString inputs.nix-secrets) + "/sops";
  homeDirectory = config.home.homeDirectory;
in
{
  imports = [ inputs.sops-nix.homeManagerModules.sops ];

  sops = {
    # This age key is bootstrapped by the system-level sops configuration
    # See hosts/common/core/sops-darwin.nix or sops-nixos.nix
    age.keyFile = "${homeDirectory}/.config/sops/age/keys.txt";

    defaultSopsFile = "${sopsFolder}/${config.hostSpec.hostName}.yaml";
    validateSopsFiles = false;

    secrets = {
      # Nix access tokens for private repos
      # formatted as extra-access-tokens = github.com=<PAT token>
      # NOTE: Commented out because 'tokens' key doesn't exist in shared.yaml yet
      # "tokens/nix-access-tokens" = {
      #   sopsFile = "${sopsFolder}/shared.yaml";
      # };
    };
  };
}
