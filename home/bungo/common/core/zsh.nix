{
  pkgs,
  ...
}:
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    enableAutosuggestions = true;
    enableSyntaxHighlighting = true;
    shellAliases = {
      # Better ls with eza
      ls = "eza";
      ll = "eza -l";
      la = "eza -la";
      lt = "eza --tree";

      # Better cat with bat
      # cat = "bat";

      # Better grep with ripgrep
      grep = "rg";

      # Navigation
      ".." = "cd ..";
      "..." = "cd ../..";
    };
  };

  home.packages = with pkgs; [
    eza
    bat
    ripgrep
  ];
}
