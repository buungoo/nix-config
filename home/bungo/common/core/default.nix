# Bungo-specific home-manager configuration across all hosts
{
  config,
  lib,
  pkgs,
  hostSpec,
  ...
}:
let
  platform = if hostSpec.isDarwin then "darwin" else "nixos";
in
{
  imports = [
    ./${platform}.nix # Platform-specific config
    ./ssh.nix
    ./zoxide.nix
    ./btop.nix
    ./zsh.nix
    ./dua.nix
    ./nvim.nix
  ];

  home = {
    sessionPath = [
      "$HOME/.local/bin"
    ];
  };

  programs = {

    git = {
      enable = true;
      settings = {
        user.email = hostSpec.users.bungo.userEmail;
        user.name = hostSpec.users.bungo.fullName;
        init.defaultBranch = "main";
      };
      ignores = [
        ".DS_Store"
      ];
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
