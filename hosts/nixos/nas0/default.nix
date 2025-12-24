{
  inputs,
  outputs,
  lib,
  pkgs,
  config,
  ...
}:
{
  nixpkgs.hostPlatform = "x86_64-linux";

  # Use latest stable kernel (6.18.2) for SMB over QUIC support (requires >= 6.14)
  boot.kernelPackages = pkgs.linuxPackages_latest;

  imports = lib.flatten [
    inputs.disko.nixosModules.disko

    (map lib.custom.relativeToRoot [
      "hosts/common/core"
      "hosts/common/optional/services/wireguard.nix"
      "hosts/common/optional/intel-graphics.nix"
      "hosts/common/optional/recyclarr.nix"
      "hosts/nixos/nas0/hardware-configuration.nix"
      "hosts/nixos/nas0/btrfs-storage.nix"
      "hosts/nixos/nas0/users.nix"

      # Custom modules
      "modules/services/snapraid-btrfs.nix"
      "modules/services/snapraid-btrfs-runner.nix"

      "hosts/common/optional/services/unbound.nix"
      "hosts/common/optional/services/samba.nix"
      "hosts/common/optional/containers/step-ca.nix"
      "hosts/common/optional/containers/immich.nix"
      # "hosts/common/optional/containers/jellyfin.nix"
      "hosts/common/optional/containers/kanidm.nix"
      "hosts/common/optional/containers/sonarr.nix"
      "hosts/common/optional/containers/radarr.nix"
      "hosts/common/optional/containers/prowlarr.nix"
      "hosts/common/optional/containers/qbittorrent.nix"
      "hosts/common/optional/containers/jellyseer.nix"
      "hosts/common/optional/containers/bazarr.nix"
      "hosts/common/optional/containers/monitoring.nix"

      "hosts/common/optional/services/haproxy.nix"
    ])
  ];

  # Host specifications
  hostSpec = {
    hostName = "nas0";
    hostAlias = "Grogu";
    stateVersion = "25.05";
    isServer = true;

    # Infrastructure configuration from nix-secrets
    domain = inputs.nix-secrets.shared.domain;

    # GPU configuration for hardware acceleration
    gpu = {
      renderDevice = "/dev/dri/renderD128";
      cardDevice = "/dev/dri/card1";
    };

    # Networking configuration
    networking = {
      externalInterfaces = [
        "enp3s0"
        "enp4s0"
      ];
      localIP = inputs.nix-secrets.nas0.networking.localIP;
      localSubnet = inputs.nix-secrets.nas0.networking.localSubnet;
      localIPv6Subnet = inputs.nix-secrets.nas0.networking.localIPv6Subnet;
      wireguardIPv4Subnet = inputs.nix-secrets.nas0.networking.wireguardIPv4Subnet;
      wireguardIPv6Subnet = inputs.nix-secrets.nas0.networking.wireguardIPv6Subnet;
    };

    # Users are now defined in ./users.nix
  };

  system.stateVersion = config.hostSpec.stateVersion;

  # Host-specific packages
  environment.systemPackages = with pkgs; [
    lazydocker # Docker management TUI
    mergerfs # Filesystem for combining drives
    step-ca-enroll # OIDC enrollment service for step-ca client certificates
    inputs.ghostty.packages.${pkgs.system}.default # Provides terminfo for SSH from Ghostty
  ];

  services.scrutiny = {
    enable = true;
    openFirewall = true;
    settings.web.listen = {
      host = "0.0.0.0";
      port = 5532;
    };
  };

  services.glance = {
    enable = true;
    openFirewall = true;
    settings = {
      server = {
        host = "0.0.0.0";
        port = 5533;
      };
      theme = {
        # Kanagawa-ish theme
        background-color = "240 13 14";
        primary-color = "39 66 71";
        negative-color = "358 100 68";
        contrast-multiplier = 1.5;
      };
      pages = [
        {
          name = "Home";
          # hide-desktop-navigation = true;
          columns = [
            {
              size = "small";
              widgets = [
                {
                  type = "weather";
                  location = "London, United Kingdom";
                  units = "metric";
                  "hour-format" = "12h";
                  # hide-location = true;
                }
                {
                  type = "calendar";
                  "first-day-of-week" = "monday";
                }
              ];
            }
            {
              size = "full";
              widgets = [
                {
                  type = "group";
                  widgets = [
                    {
                      type = "reddit";
                      subreddit = "selfhosted";
                      "show-thumbnails" = true;
                      "collapse-after" = -1;
                    }
                  ];
                }
              ];
            }
            {
              size = "small";
              widgets = [

                {
                  type = "releases";
                  cache = "1d";
                  # token = "...";
                  repositories = [
                    "glanceapp/glance"
                    "immich-app/immich"
                    "jellyfin/jellyfin"
                  ];
                }
              ];
            }
          ];
        }
      ];
    };
  };

  # services = {
  #   openssh = {
  #     enable = true;
  #     settings = {
  #       LogLevel = "VERBOSE";
  #       PasswordAuthentication = true; # Disable password authentication
  #       PermitRootLogin = "prohibit-password"; # Only allow root login with SSH keys
  #       KbdInteractiveAuthentication = false; # Disable interactive authentication
  #     };
  #   };
  # };

  # set the CPU scaling governor system-wide - Commented this out because I think the machine handles this automatically? The BIOS suggests so
  # Check p-state policy: cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor
  # check c-state policy: cat /sys/devices/system/cpu/cpuidle/current_driver
  # powerManagement.enable = true;
  # powerManagement.cpuFreqGovernor = "performance";
}
