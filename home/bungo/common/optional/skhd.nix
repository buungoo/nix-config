# skhd hotkey daemon configuration (home-manager)
{
  pkgs,
  lib,
  ...
}:
{
  services.skhd = {
    enable = true;
    package = pkgs.skhd;

    config = ''
      # ===== Switch spaces =====
      fn - 1 : yabai -m space --focus 1
      fn - 2 : yabai -m space --focus 2
      fn - 3 : yabai -m space --focus 3
      fn - 4 : yabai -m space --focus 4
      fn - 5 : yabai -m space --focus 5
      fn - 6 : yabai -m space --focus 6
      fn - 7 : yabai -m space --focus 7
      fn - 8 : yabai -m space --focus 8
      fn - 9 : yabai -m space --focus 9
      fn - 0 : yabai -m space --focus 10

      # ===== Focus windows =====
      fn - h : yabai -m window --focus west
      fn - j : yabai -m window --focus south
      fn - k : yabai -m window --focus north
      fn - l : yabai -m window --focus east

      # Focus window in stack
      fn - n : yabai -m window --focus stack.next || yabai -m window --focus stack.first
      fn - p : yabai -m window --focus stack.prev || yabai -m window --focus stack.last

      # ===== Move windows =====
      shift + fn - h : yabai -m window --swap west
      shift + fn - j : yabai -m window --swap south
      shift + fn - k : yabai -m window --swap north
      shift + fn - l : yabai -m window --swap east

      # Move window to space (i3-style with Option key)
      shift + fn - 1 : yabai -m window --space 1
      shift + fn - 2 : yabai -m window --space 2
      shift + fn - 3 : yabai -m window --space 3
      shift + fn - 4 : yabai -m window --space 4
      shift + fn - 5 : yabai -m window --space 5
      shift + fn - 6 : yabai -m window --space 6
      shift + fn - 7 : yabai -m window --space 7
      shift + fn - 8 : yabai -m window --space 8
      shift + fn - 9 : yabai -m window --space 9
      shift + fn - 0 : yabai -m window --space 10

      # ===== Resize windows =====
      ctrl + fn - h : yabai -m window --resize left:-50:0 || yabai -m window --resize right:-50:0
      ctrl + fn - j : yabai -m window --resize bottom:0:50 || yabai -m window --resize top:0:50
      ctrl + fn - k : yabai -m window --resize top:0:-50 || yabai -m window --resize bottom:0:-50
      ctrl + fn - l : yabai -m window --resize right:50:0 || yabai -m window --resize left:50:0

      # Balance window sizes
      shift + fn - b : yabai -m space --balance

      # ===== Layout =====
      # Toggle between bsp and float for current window
      fn - t : yabai -m window --toggle float

      # Toggle split direction
      fn - e : yabai -m window --toggle split

      # Rotate tree 90 degrees
      fn - r : yabai -m space --rotate 90

      # Mirror tree on x/y axis
      shift + fn - x : yabai -m space --mirror x-axis
      shift + fn - y : yabai -m space --mirror y-axis

      # Change layout of desktop
      ctrl + fn - b : yabai -m space --layout bsp
      ctrl + fn - f : yabai -m space --layout float
      ctrl + fn - s : yabai -m space --layout stack

      # ===== Fullscreen =====
      fn - f : yabai -m window --toggle zoom-fullscreen
      shift + fn - f : yabai -m window --toggle native-fullscreen

      # ===== Application control =====
      # Launch Raycast
      fn - d : open -a "Raycast"

      # Close focused window
      fn - q : yabai -m window --close

      # ===== Restart services =====
      ctrl + fn - r : yabai --restart-service
    '';
  };
}
