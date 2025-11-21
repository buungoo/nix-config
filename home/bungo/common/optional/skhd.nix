{
  pkgs,
  lib,
  ...
}:
{
  # Works with yabai for window management keybindings

  home.packages = [ pkgs.skhd ];

  # skhd configuration
  xdg.configFile."skhd/skhdrc".text = ''
    # ===== Focus windows =====
    alt - h : yabai -m window --focus west
    alt - j : yabai -m window --focus south
    alt - k : yabai -m window --focus north
    alt - l : yabai -m window --focus east

    # Focus window in stack
    alt - n : yabai -m window --focus stack.next || yabai -m window --focus stack.first
    alt - p : yabai -m window --focus stack.prev || yabai -m window --focus stack.last

    # ===== Move windows =====
    shift + alt - h : yabai -m window --swap west
    shift + alt - j : yabai -m window --swap south
    shift + alt - k : yabai -m window --swap north
    shift + alt - l : yabai -m window --swap east

    # Move window to space
    shift + alt - 1 : yabai -m window --space 1
    shift + alt - 2 : yabai -m window --space 2
    shift + alt - 3 : yabai -m window --space 3
    shift + alt - 4 : yabai -m window --space 4
    shift + alt - 5 : yabai -m window --space 5

    # ===== Resize windows =====
    ctrl + alt - h : yabai -m window --resize left:-50:0 || yabai -m window --resize right:-50:0
    ctrl + alt - j : yabai -m window --resize bottom:0:50 || yabai -m window --resize top:0:50
    ctrl + alt - k : yabai -m window --resize top:0:-50 || yabai -m window --resize bottom:0:-50
    ctrl + alt - l : yabai -m window --resize right:50:0 || yabai -m window --resize left:50:0

    # Balance window sizes
    shift + alt - 0 : yabai -m space --balance

    # ===== Layout =====
    # Toggle between bsp and float for current window
    alt - t : yabai -m window --toggle float

    # Toggle split direction
    alt - e : yabai -m window --toggle split

    # Rotate tree 90 degrees
    alt - r : yabai -m space --rotate 90

    # Mirror tree on x/y axis
    shift + alt - x : yabai -m space --mirror x-axis
    shift + alt - y : yabai -m space --mirror y-axis

    # Change layout of desktop
    ctrl + alt - b : yabai -m space --layout bsp
    ctrl + alt - f : yabai -m space --layout float
    ctrl + alt - s : yabai -m space --layout stack

    # ===== Fullscreen =====
    alt - f : yabai -m window --toggle zoom-fullscreen
    shift + alt - f : yabai -m window --toggle native-fullscreen

    # ===== Application control =====
    alt - q : osascript -e 'tell application (path to frontmost application as text) to quit'

    # ===== Restart services =====
    ctrl + alt - r : yabai --restart-service
  '';

  # Launch agent for skhd
  launchd.agents.skhd = {
    enable = true;
    config = {
      Label = "com.koekeishiya.skhd";
      ProgramArguments = [
        "${pkgs.skhd}/bin/skhd"
        "-c"
        "/Users/bungo/.config/skhd/skhdrc"
      ];
      EnvironmentVariables = {
        PATH = "${pkgs.yabai}/bin:${pkgs.skhd}/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
      };
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/tmp/skhd.out.log";
      StandardErrorPath = "/tmp/skhd.err.log";
    };
  };
}
