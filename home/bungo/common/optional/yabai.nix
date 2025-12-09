# readlink -f $(which yabai)
{
  pkgs,
  lib,
  ...
}:
{
  # For advanced features (borders, opacity, title bar removal), SIP must be partially disabled
  # Note: yabai is managed via launchd.agents below
  # But we keep it in home.packages so the binary is in PATH for the shell commands

  home.packages = [ pkgs.yabai ];

  # yabai configuration
  xdg.configFile."yabai/yabairc" = {
    executable = true;
    text = ''
      #!/usr/bin/env sh

      # Layout settings
      yabai -m config layout bsp
      yabai -m config window_placement second_child

      # Padding and gaps
      yabai -m config top_padding    2
      yabai -m config bottom_padding 2
      yabai -m config left_padding   2
      yabai -m config right_padding  2
      yabai -m config window_gap     2

      # Mouse settings
      yabai -m config mouse_follows_focus off
      yabai -m config focus_follows_mouse off
      yabai -m config mouse_modifier alt
      yabai -m config mouse_action1 move
      yabai -m config mouse_action2 resize
      yabai -m config mouse_drop_action swap

      # Window settings
      yabai -m config split_ratio 0.50
      yabai -m config split_type auto
      yabai -m config auto_balance off

      # Rules for apps that shouldn't tile
      yabai -m rule --add app="^System Settings$" manage=off
      yabai -m rule --add app="^System Preferences$" manage=off
      yabai -m rule --add app="^Calculator$" manage=off
      yabai -m rule --add app="^Karabiner-Elements$" manage=off
      yabai -m rule --add app="^Archive Utility$" manage=off
      yabai -m rule --add app="^Finder$" title="(Co(py|nnect)|Move|Info|Pref)" manage=off
      yabai -m rule --add app="^Alfred Preferences$" manage=off
      yabai -m rule --add app="^1Password$" manage=off
      yabai -m rule --add app="^Raycast$" manage=off
      yabai -m rule --add app="^FaceTime$" manage=off

      echo "yabai configuration loaded"
    '';
  };

  # Launch agent for yabai
  launchd.agents.yabai = {
    enable = true;
    config = {
      Label = "com.koekeishiya.yabai";
      ProgramArguments = [
        "${pkgs.yabai}/bin/yabai"
        "-c"
        "/Users/bungo/.config/yabai/yabairc"
      ];
      EnvironmentVariables = {
        PATH = "${pkgs.yabai}/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
      };
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/tmp/yabai.out.log";
      StandardErrorPath = "/tmp/yabai.err.log";
    };
  };
}
