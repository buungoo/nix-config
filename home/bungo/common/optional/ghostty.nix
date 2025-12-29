{
  pkgs,
  inputs,
  hostSpec,
  lib,
  ...
}:
let
  cursorTailShader = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/sahaj-b/ghostty-cursor-shaders/main/cursor_tail.glsl";
    sha256 = "sha256-3BCfBPpraGfRC2gcBVWijQJZSct9tp+NB5Jt2/XSO70=";
  };
  cursorWarpShader = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/sahaj-b/ghostty-cursor-shaders/main/cursor_warp.glsl";
    sha256 = "sha256-daQ639BJyPxvJJgs5jHUnz0AWgBnqBr/YA7G6G/BTeE=";
  };
  bloomShader = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/0xhckr/ghostty-shaders/refs/heads/main/bloom.glsl";
    sha256 = "sha256-9r5suoOrO6EMXJ5d8rKfncQF/OMufVPg1LreC+DDiM8=";
  };
in
{
  # Ghostty terminal emulator
  programs.ghostty = {
    enable = true;
    package = if hostSpec.isDarwin then pkgs.brewCasks.ghostty else pkgs.ghostty;

    settings = {
      theme = "Kanagawa Wave";
      font-family = "Menlo";
      background-opacity = 0.98;
      custom-shader = [
        "${cursorWarpShader}"
      ];
      custom-shader-animation = "always";
      resize-overlay = "never";
    }
    // lib.optionalAttrs hostSpec.isDarwin {
      macos-titlebar-style = "hidden";
    }
    // lib.optionalAttrs (!hostSpec.isDarwin) {
      window-decoration = "none";
    };
  };
}
