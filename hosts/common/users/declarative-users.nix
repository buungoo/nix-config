# Declarative user creation based on hostSpec.users
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf mapAttrs mapAttrsToList;

  # Get users from hostSpec
  hostUsers = config.hostSpec.users;
in
{
  # Only allow declarative credentials; Required for password to be set via sops during system activation!
  users.mutableUsers = false;
  # Create users for each one defined in hostSpec.users
  users.users = mapAttrs (
    username: userConfig:
    let
      # Get the sops-decrypted password path (like emergent does)
      sopsHashedPasswordFile =
        lib.optionalString (builtins.hasAttr "passwords/${username}" config.sops.secrets)
          config.sops.secrets."passwords/${username}".path;
    in
    {
      isNormalUser = !userConfig.isSystemUser;
      isSystemUser = userConfig.isSystemUser;
      description = userConfig.fullName;
      extraGroups = userConfig.groups;

      # Use password from secrets if available
      hashedPasswordFile = mkIf (sopsHashedPasswordFile != "") sopsHashedPasswordFile;

      # Set shell
      shell = pkgs.${userConfig.shell};

      # Add SSH public keys from hostSpec.users.<name>.sshKeys
      openssh.authorizedKeys.keys = lib.attrValues (userConfig.sshKeys or { });
    }
  ) hostUsers;
}
