# Darwin-specific sops configuration
{
  pkgs,
  lib,
  inputs,
  config,
  ...
}:
let
  sopsFolder = builtins.toString inputs.nix-secrets + "/sops";

  # Find the primary user
  primaryUser = builtins.head (
    lib.attrNames (lib.filterAttrs (_: user: user.primary or false) config.hostSpec.users)
  );
  primaryUserConfig = config.hostSpec.users.${primaryUser};
in
{
  sops = {
    defaultSopsFile = "${sopsFolder}/${config.hostSpec.hostName}.yaml";
    validateSopsFiles = false;
    age = {
      # Use system SSH host key for decryption
      sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    };
    # secrets will be output to /run/secrets
  };

  # Bootstrap age key for home-manager from the system-decrypted secret
  # This allows home-manager to decrypt its own secrets
  sops.secrets = {
    "keys/age" = {
      sopsFile = "${sopsFolder}/shared.yaml";
      owner = primaryUser;
      group = "staff"; # Darwin uses 'staff' group
      path = "${primaryUserConfig.home}/.config/sops/age/keys.txt";
    };
  };

  # Create the containing folder with proper ownership
  # On Darwin, we need to ensure the .config/sops/age directory exists and has correct permissions
  system.activationScripts.postActivation.text = lib.mkAfter ''
    ageFolder="${primaryUserConfig.home}/.config/sops/age"
    user="${primaryUser}"

    # Create directory if it doesn't exist
    mkdir -p "$ageFolder" || true

    # Fix ownership of entire .config directory
    chown -R "$user:staff" "${primaryUserConfig.home}/.config" || true
  '';
}
