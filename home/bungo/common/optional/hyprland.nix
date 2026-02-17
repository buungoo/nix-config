{
  pkgs,
  lib,
  ...
}:
{
  # imports = lib.flatten [
  #   (map lib.custom.relativeToRoot [
  #     "home/bungo/common/optional/waybar.nix"
  #     "home/bungo/common/optional/quickshell.nix"
  #   ])
  # ];
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.hyprland = {
      default = [
        "hyprland"
        "gtk"
      ];
      "org.freedesktop.impl.portal.Secret" = [ "gnome-keyring" ];
    };
  };

  programs.hyprlock.enable = true;

  wayland.windowManager.hyprland = {
    enable = true;

    settings = {
      "$mod" = "SUPER";

      exec-once = [
        "neowall"
        "noctalia-shell"
        "nm-applet --indicator"
        "blueman-applet"
      ];

      monitor = [
        "desc:Xiaomi Corporation Mi Monitor, 3440x1440@120, 0x0, 1"
        ", preferred, auto, 1"
      ];

      general = {
        gaps_in = 5;
        gaps_out = 10;
        border_size = 2;
        layout = "dwindle";
      };

      decoration = {
        rounding = 10;
      };

      animations = {
        enabled = true;
        animation = [
          "workspaces, 0"
        ];
      };

      input = {
        kb_layout = "se";
        follow_mouse = 0;
        touchpad = {
          natural_scroll = true;
        };
        repeat_delay = 140;
        repeat_rate = 25;
      };

      bind = [
        "$mod, Return, exec, ghostty"
        "$mod, Q, killactive"
        "$mod, M, exit"
        "$mod, E, exec, dolphin"
        "$mod, V, togglefloating"
        "$mod, D, exec, walker"
        "$mod, F, fullscreen, 1"

        # Move focus
        "$mod, H, movefocus, l"
        "$mod, J, movefocus, d"
        "$mod, K, movefocus, u"
        "$mod, L, movefocus, r"
        "$mod, LEFT, movefocus, l"
        "$mod, DOWN, movefocus, d"
        "$mod, UP, movefocus, u"
        "$mod, RIGHT, movefocus, r"

        # Move windows
        "$mod SHIFT, H, movewindow, l"
        "$mod SHIFT, J, movewindow, d"
        "$mod SHIFT, K, movewindow, u"
        "$mod SHIFT, L, movewindow, r"
        "$mod SHIFT, LEFT, movewindow, l"
        "$mod SHIFT, DOWN, movewindow, d"
        "$mod SHIFT, UP, movewindow, u"
        "$mod SHIFT, RIGHT, movewindow, r"

        # Workspaces
        "$mod, 1, workspace, 1"
        "$mod, 2, workspace, 2"
        "$mod, 3, workspace, 3"
        "$mod, 4, workspace, 4"
        "$mod, 5, workspace, 5"
        "$mod, 6, workspace, 6"
        "$mod, 7, workspace, 7"
        "$mod, 8, workspace, 8"
        "$mod, 9, workspace, 9"
        "$mod, 0, workspace, 10"

        # Move to workspace
        "$mod SHIFT, 1, movetoworkspace, 1"
        "$mod SHIFT, 2, movetoworkspace, 2"
        "$mod SHIFT, 3, movetoworkspace, 3"
        "$mod SHIFT, 4, movetoworkspace, 4"
        "$mod SHIFT, 5, movetoworkspace, 5"
        "$mod SHIFT, 6, movetoworkspace, 6"
        "$mod SHIFT, 7, movetoworkspace, 7"
        "$mod SHIFT, 8, movetoworkspace, 8"
        "$mod SHIFT, 9, movetoworkspace, 9"
        "$mod SHIFT, 0, movetoworkspace, 10"
      ];
    };
  };

  services.gnome-keyring = {
    enable = true;
    components = [
      "secrets"
      "pkcs11"
    ];
  };

  home.packages = with pkgs; [
    blueman
    networkmanagerapplet
    wofi
    hyprpaper
    gnome-keyring
  ];
}
