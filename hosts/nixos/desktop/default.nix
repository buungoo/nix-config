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

      # Hardware
      "hosts/nixos/common/optional/nvidia.nix"

      # Optional modules
      "hosts/common/optional/audio.nix"
      "hosts/common/optional/bluetooth.nix"
      "hosts/common/optional/sysc-greet.nix"
      # "hosts/common/optional/tuigreet.nix"
      "hosts/common/optional/opengamepadui.nix"
      "hosts/common/optional/steam.nix"
      "hosts/common/optional/services/wireguard-client.nix"
    ])
  ];

  # SMB over QUIC client for remote NAS access
  custom.services.sambaClient = {
    enable = true;
    tlsCertFile = config.sops.secrets."samba-client/cert".path;
    tlsKeyFile = config.sops.secrets."samba-client/key".path;
    credentials.samba_media = {
      username = "samba_media";
      passwordFile = config.sops.secrets."samba-client/samba_media".path;
    };
  };

  sops.secrets = {
    "samba-client/cert".mode = "0644";
    "samba-client/key" = {
      mode = "0640";
      group = "users";
    };
    "samba-client/samba_media".mode = "0400";
  };

  networking.networkmanager.enable = true;

  environment.systemPackages = [
    inputs.librepods.packages.${pkgs.system}.default # AirPods management
    pkgs.pulsemixer # TUI audio mixer
    pkgs.wiremix
    pkgs.wl-clipboard
  ];

  # Enable CUPS to print documents.
  services.printing.enable = true;

  programs = {
    hyprland.enable = true;
    noisetorch.enable = true;
    firefox.enable = true;
    kdeconnect.enable = true;
  };

  services.netbird.clients.desktop = {
    port = 51820;
    interface = "nb-desktop";
    logLevel = "info";
    config = {
      ManagementURL = {
        Scheme = "https";
        Host = "netbird.bungos.xyz:443";
      };
    };
  };

  # Ensure the UI wrapper is present for SSO login on a non-X11 desktop.
  services.netbird.ui.enable = true;

  # Allow the desktop user to talk to the hardened NetBird daemon socket.
  users.users.bungo.extraGroups = lib.mkAfter [ "netbird-desktop" ];

  # Allow the desktop user (in netbird-desktop group) to read the state dir
  # so `netbird-desktop login` can access /var/lib/netbird-desktop/default.json.
  systemd.services.netbird-desktop.serviceConfig.StateDirectoryMode = lib.mkForce "0750";

  hostSpec = {
    hostName = "desktop";
    hostAlias = "Meshy";
    stateVersion = "25.11";
  };

  system.stateVersion = config.hostSpec.stateVersion;
}
