{
  pkgs,
  ...
}:
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    sessionVariables = {
      LANGUAGE = "en";
    };
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
      "-" = "cd -";
    };
  };

  programs.starship = {
    enable = true;
    enableZshIntegration = true;
  };

  home.packages = with pkgs; [
    eza
    bat
    ripgrep
  ];
}
