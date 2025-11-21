{ pkgs, hostSpec, lib, ... }:
{
  # Raycast - Spotlight replacement with extensions
  # Configure hotkey in Raycast settings (recommend: Option+Space)
  # Add Nix paths in Raycast settings for app indexing:
  #   ~/.nix-profile/Applications
  #   /run/current-system/Applications
  home.packages = lib.optionals hostSpec.isDarwin [
    pkgs.raycast
  ];
}
