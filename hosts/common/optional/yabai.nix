# yabai window manager configuration (nix-darwin system-level)
{
  pkgs,
  lib,
  config,
  ...
}:
let
  yabaiPackage = config.services.yabai.package;
in
{
  services.yabai = {
    enable = true;
    package = pkgs.yabai;
    enableScriptingAddition = true;

    config = {
      # Layout settings
      layout = "bsp";
      window_placement = "second_child";

      # Padding and gaps
      top_padding = 2;
      bottom_padding = 2;
      left_padding = 2;
      right_padding = 2;
      window_gap = 2;

      # Mouse settings
      mouse_follows_focus = "off";
      focus_follows_mouse = "off";
      mouse_modifier = "alt";
      mouse_action1 = "move";
      mouse_action2 = "resize";
      mouse_drop_action = "swap";

      # Window settings
      split_ratio = 0.50;
      split_type = "auto";
      auto_balance = "off";
    };

    extraConfig = ''
      # Load scripting addition on startup
      sudo ${yabaiPackage}/bin/yabai --load-sa

      # Reload scripting addition when Dock restarts
      yabai -m signal --add event=dock_did_restart action="sudo ${yabaiPackage}/bin/yabai --load-sa"

      # Rules for apps that shouldn't tile
      yabai -m rule --add app="^System Settings$" manage=off
      yabai -m rule --add app="^System Preferences$" manage=off
      yabai -m rule --add app="^Calculator$" manage=off
      yabai -m rule --add app="^Archive Utility$" manage=off
      yabai -m rule --add app="^Finder$" title="(Co(py|nnect)|Move|Info|Pref)" manage=off
      yabai -m rule --add app="^Raycast$" manage=off
      yabai -m rule --add app="^FaceTime$" manage=off
      yabai -m rule --add app="^SketchyBar$" manage=off sticky=on layer=above

      echo "yabai configuration loaded"
    '';
  };
}
