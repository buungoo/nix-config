# sketchybar status bar (home-manager)
{
  pkgs,
  lib,
  ...
}:
{
  programs.sketchybar = {
    enable = true;
    package = pkgs.sketchybar;

    config = ''
      #!/usr/bin/env sh

      # Configure bar appearance
      sketchybar --bar height=32 \
                       position=top \
                       sticky=on \
                       padding_left=10 \
                       padding_right=10 \
                       color=0xff1e1e2e

      # Set default item properties
      sketchybar --default updates=when_shown \
                           drawing=on

      # Workspace/Space configuration
      SPACE_ICONS=("1" "2" "3" "4" "5" "6" "7" "8" "9" "10")

      for i in {1..10}
      do
        sketchybar --add space space.$i left \
                   --set space.$i associated_space=$i \
                                  icon=''${SPACE_ICONS[$i-1]} \
                                  icon.padding_left=20 \
                                  icon.padding_right=20 \
                                  icon.highlight_color=0xffE48FA8 \
                                  background.padding_left=-4 \
                                  background.padding_right=-4 \
                                  background.color=0xff3C3E4F \
                                  background.drawing=on \
                                  label.drawing=off \
                                  click_script="yabai -m space --focus $i"
      done

      # Add separator after spaces
      sketchybar --add item space_separator left \
                 --set space_separator icon= \
                                       background.padding_left=23 \
                                       background.padding_right=23 \
                                       label.drawing=off \
                                       icon.color=0xff92B3F5

      # Finalize configuration
      sketchybar --update
    '';
  };
}
