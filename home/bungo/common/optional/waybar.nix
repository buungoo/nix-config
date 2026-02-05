{ pkgs, ... }:
{
  programs.waybar = {
    enable = true;
    systemd.enable = true;
    settings = {
      mainBar = {
        layer = "top";
        position = "top";
        height = 30;
        modules-left = [ "hyprland/workspaces" ];
        modules-center = [ "clock" ];
        modules-right = [
          "network"
          "bluetooth"
          "pulseaudio"
          "battery"
        ];

        network = {
          format-wifi = "  {signalStrength}%";
          format-ethernet = "󰈀";
          format-disconnected = "󰖪";
          tooltip-format = "{ifname}: {ipaddr}";
          on-click = "nm-connection-editor";
        };

        bluetooth = {
          format = "󰂯";
          format-connected = "󰂱 {device_alias}";
          format-disabled = "󰂲";
          tooltip-format = "{status}";
          on-click = "blueman-manager";
        };

        pulseaudio = {
          format = "{icon} {volume}%";
          format-muted = "󰝟";
          format-icons = {
            default = [
              "󰕿"
              "󰖀"
              "󰕾"
            ];
          };
          on-click = "pavucontrol";
        };

        battery = {
          format = "{icon} {capacity}%";
          format-icons = [
            "󰁺"
            "󰁻"
            "󰁼"
            "󰁽"
            "󰁾"
            "󰁿"
            "󰂀"
            "󰂁"
            "󰂂"
            "󰁹"
          ];
        };

        clock = {
          format = "{:%H:%M}";
          format-alt = "{:%Y-%m-%d}";
        };
      };
    };
    style = ''
      * {
        font-family: "Menlo", monospace;
        font-size: 13px;
      }

      window#waybar {
        background: rgba(30, 30, 46, 0.9);
        color: #cdd6f4;
      }

      #workspaces button {
        padding: 0 5px;
        color: #cdd6f4;
      }

      #workspaces button.active {
        color: #a6e3a1;
      }

      #network, #bluetooth, #pulseaudio, #battery, #clock {
        padding: 0 10px;
      }
    '';
  };

  home.packages = with pkgs; [
    pavucontrol
  ];
}
