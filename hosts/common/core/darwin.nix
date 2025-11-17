# Darwin-specific core configuration
{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Basic services
  services.nix-daemon.enable = true;

  # System packages
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
  ];
}
