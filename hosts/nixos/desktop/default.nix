# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
{

  imports = lib.flatten [
    (map lib.custom.relativeToRoot [
      "hosts/nixos/desktop/hardware-configuration.nix"
      "hosts/common/core"
      "hosts/nixos/desktop/users.nix"

      "hosts/nixos/common/optional/nvidia.nix"
    ])
  ];

  boot.loader.efi.canTouchEfiVariables = true;
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Enable networking
  networking.networkmanager.enable = true;

  services.blueman.enable = true;
  hardware.bluetooth.enable = true;
  services.hardware.openrgb.enable = true;

  environment.systemPackages = [
    inputs.librepods.packages.${pkgs.system}.default # AirPods management
    pkgs.pulsemixer # TUI audio mixer
    pkgs.wiremix
    pkgs.wl-clipboard
  ];

  # Enable the X11 windowing system.
  # You can disable this if you're only using the Wayland session.
  services.xserver.enable = true;

  # Enable the KDE Plasma Desktop Environment.
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Keyring for Hyprland sessions
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.sddm.enableGnomeKeyring = true;

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;

    # Enable analog audio on motherboard
    # wpctl status
    # wpctl inspect <id>
    # pactl list cards
    wireplumber.extraConfig = {
      "10-enable-motherboard-audio" = {
        "monitor.alsa.rules" = [
          {
            matches = [ { "device.name" = "alsa_card.pci-0000_0a_00.4"; } ];
            actions.update-props."device.profile" = "output:analog-stereo+input:analog-stereo";
          }
        ];
      };

      # Bluetooth codec configuration
      "11-bluetooth-tweaks" = {
        "monitor.bluez.properties" = {
          # Codecs
          "bluez5.enable-sbc-xq" = true;
          "bluez5.enable-msbc" = true;
          "bluez5.enable-aac" = true;
          "bluez5.enable-aptx" = true;
          "bluez5.enable-aptx-hd" = true;
          "bluez5.enable-ldac" = true;

          # Features
          "bluez5.enable-hw-volume" = true;
          "bluez5.auto-switch-profile" = true;
        };
      };
    };
  };

  programs = {
    hyprland.enable = true;
    noisetorch.enable = true;
    firefox.enable = true;
    kdeconnect.enable = true;
    steam = {
      enable = true;
      remotePlay.openFirewall = true;
      dedicatedServer.openFirewall = true;
    };
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).

  hostSpec = {
    hostName = "desktop";
    hostAlias = "Meshy";
    stateVersion = "25.11";
  };

  system.stateVersion = config.hostSpec.stateVersion;
}
