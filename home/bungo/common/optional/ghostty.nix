{ pkgs, inputs, hostSpec, lib, ... }:
let
  cursorTailShader = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/sahaj-b/ghostty-cursor-shaders/main/cursor_tail.glsl";
    sha256 = "sha256-3BCfBPpraGfRC2gcBVWijQJZSct9tp+NB5Jt2/XSO70=";
  };
  cursorWarpShader = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/sahaj-b/ghostty-cursor-shaders/main/cursor_warp.glsl";
    sha256 = "sha256-daQ639BJyPxvJJgs5jHUnz0AWgBnqBr/YA7G6G/BTeE=";
  };
in
{
  # Ghostty terminal emulator
  programs.ghostty = {
    enable = true;
    package = if hostSpec.isDarwin
      then pkgs.brewCasks.ghostty
      else inputs.ghostty.packages.${pkgs.system}.default;
    settings = {
      theme = "Kanagawa Wave";
      font-family = "Menlo";
      background-opacity = 0.98;
      window-decoration = "none"; # window manager should handle this?
      # custom-shader = "${cursorTailShader}";
      custom-shader = "${cursorWarpShader}";
      custom-shader-animation = "always";
      resize-overlay = "never";
    };
  };
}
