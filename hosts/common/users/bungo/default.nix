{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
  ];

  # User account configuration
  users.users.bungo = {
    isNormalUser = true;
    description = config.hostSpec.userFullName;
    extraGroups = [
      "networkmanager"
      "wheel"
      "docker"
    ];

    # Use password from secrets
    hashedPasswordFile = "/run/secrets-for-users/passwords/bungo";

    openssh.authorizedKeys.keys = [
    ];
  };

  home-manager.users.bungo = import ../../../../home/bungo/common/core;
}
