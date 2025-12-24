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
  nixpkgs.overlays = lib.mkAfter [
    inputs.brew-nix.overlays.default
    # Fix for Vivaldi .tar.xz extraction (must run after brew-nix)
    (final: prev: {
      brewCasks = prev.brewCasks // {
        vivaldi = prev.brewCasks.vivaldi.overrideAttrs (old: {
          # Fix unpackPhase for .tar.xz files
          # brew-nix's default uses 7zz which only extracts the .xz layer
          # We need to extract both .xz and .tar
          unpackPhase = ''
            # Try standard methods first
            undmg $src || unzip $src || {
              # For .tar.xz files, extract in two stages
              if [[ $src == *.tar.xz ]]; then
                7zz x $src
                tar xf *.tar
                rm *.tar
              else
                7zz x -snld $src
              fi
            }
          '';
        });
      };
    })
  ];

  # Use Touch ID for sudo
  security.pam.services.sudo_local.touchIdAuth = lib.mkDefault true;

  # Nix settings
  nix.settings = {
    trusted-users = [ "@admin" ];
    # Enable x86_64 (Intel) support via Rosetta 2
    extra-platforms = lib.mkIf pkgs.stdenv.isAarch64 [ "x86_64-darwin" "aarch64-darwin" ];
  };

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

  # Install Rosetta 2 for x86_64 (Intel) app support on Apple Silicon
  system.activationScripts.rosetta = lib.mkIf pkgs.stdenv.isAarch64 ''
    if ! /usr/bin/pgrep oahd >/dev/null 2>&1; then
      echo "Installing Rosetta 2..."
      /usr/sbin/softwareupdate --install-rosetta --agree-to-license
    fi
  '';
}
