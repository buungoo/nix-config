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

  # Homebrew integration (optional)
  # homebrew = {
  #   enable = true;
  #   onActivation = {
  #     autoUpdate = true;
  #     cleanup = "zap";
  #   };
  #   brews = [
  #     # CLI tools not in nixpkgs
  #   ];
  #   casks = [
  #     # GUI applications
  #   ];
  # };
}
