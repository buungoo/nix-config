# Darwin-specific core configuration
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  # brew-nix overlay for Homebrew Casks as Nix packages
  nixpkgs.overlays = lib.mkAfter [ inputs.brew-nix.overlays.default ];

  # Use Touch ID for sudo
  security.pam.services.sudo_local.touchIdAuth = lib.mkDefault true;

  # Nix settings
  nix.settings.trusted-users = [ "@admin" ];

  # Use nix.optimise instead of auto-optimise-store (which corrupts store)
  nix.optimise.automatic = true;

  # Garbage collection (Darwin uses interval instead of dates)
  nix.gc = {
    automatic = true;
    interval = {
      Weekday = 0;
      Hour = 2;
      Minute = 0;
    };
    options = "--delete-generations +10";
  };
}
