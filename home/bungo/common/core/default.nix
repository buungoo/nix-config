# Bungo-specific home-manager configuration across all hosts
{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./nixos.nix # Platform-specific config
    ./ssh.nix
    ./zoxide.nix
    ./btop.nix
    ./zsh.nix
  ];

  home = {
    sessionPath = [
      "$HOME/.local/bin"
    ];
  };

  programs = {

    git = {
      enable = true;
      userEmail = "bungo@example.com";
      userName = "Bungo User";
    };

    direnv = {
      enable = true;
    };
  };

  home.packages = with pkgs; [
    fd
    fzf
    nix-tree
    fastfetch
  ];
}
