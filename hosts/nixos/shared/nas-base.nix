# Shared base configuration for all NAS hosts (nas0, nas1, etc.)
# Individual hosts import this and override hostSpec values
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

      # Custom modules
      "modules/services/snapraid-btrfs.nix"
      "modules/services/snapraid-btrfs-runner.nix"

      # Services
      "hosts/common/optional/services/unbound.nix"
      "hosts/common/optional/services/samba.nix"
      "hosts/common/optional/services/scrutiny.nix"
      "hosts/common/optional/services/glance.nix"

      # Containers
      "hosts/common/optional/containers/step-ca.nix"
      "hosts/common/optional/containers/immich.nix"
      # TODO: problems with declarative-jellyfin
      # "hosts/common/optional/containers/jellyfin.nix"
      "hosts/common/optional/containers/kanidm.nix"
      "hosts/common/optional/containers/sonarr.nix"
      "hosts/common/optional/containers/radarr.nix"
      "hosts/common/optional/containers/prowlarr.nix"
      "hosts/common/optional/containers/qbittorrent.nix"
      "hosts/common/optional/containers/jellyseer.nix"
      "hosts/common/optional/containers/bazarr.nix"
      "hosts/common/optional/containers/monitoring.nix"

      # HAProxy (must be last to ensure all service domains are defined)
      "hosts/common/optional/services/haproxy.nix"
    ])
  ];

  # Shared packages for all NAS hosts
  environment.systemPackages = with pkgs; [
    lazydocker # Docker management TUI
    mergerfs # Filesystem for combining drives
    step-ca-enroll # OIDC enrollment service for step-ca client certificates
    ghostty # Provides terminfo for SSH from Ghostty
  ];

  # Shared GPU configuration (can be overridden per-host)
  hostSpec.gpu = lib.mkDefault {
    renderDevice = "/dev/dri/renderD128";
    cardDevice = "/dev/dri/card1";
  };

  hostSpec.isServer = true;
}
