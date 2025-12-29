{
  inputs,
  outputs,
  lib,
  pkgs,
  config,
  ...
}:
{
  nixpkgs.hostPlatform = "aarch64-darwin";

  imports = lib.flatten [
    (map lib.custom.relativeToRoot [
      "hosts/common/core"
      "hosts/darwin/macbook/users.nix"
      "hosts/common/users/bungo/darwin.nix"
      "hosts/common/optional/services/wireguard-client.nix"
      "hosts/common/optional/yabai.nix"
    ])
  ];

  # Host specifications
  hostSpec = {
    hostName = "macbook";
    hostAlias = "MacBook";
    stateVersion = "25.05";
    isDarwin = true;
  };

  # nix-darwin uses system.stateVersion differently
  system.stateVersion = 5;

  # Host-specific packages
  environment.systemPackages = with pkgs; [
    # Add macbook-specific packages here
  ];

  # macOS system preferences
  system.defaults = {
    # Required for yabai: Displays have separate Spaces
    spaces.spans-displays = false;

    # Auto-hide menu bar for sketchybar
    NSGlobalDomain._HIHideMenuBar = true;

    dock = {
      # Required for yabai: Disable automatic Space rearrangement
      # This ensures space ordering remains stable for yabai commands
      mru-spaces = false;
    };

    finder = {
      # Required for yabai: Show items on desktop
      # Needed for display and space focus commands in multi-display setups
      ShowExternalHardDrivesOnDesktop = true;
      ShowHardDrivesOnDesktop = true;
      ShowMountedServersOnDesktop = true;
      ShowRemovableMediaOnDesktop = true;
    };
  };
}
