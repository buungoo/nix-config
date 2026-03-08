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
      "hosts/common/optional/services/cloudflare-dyndns.nix"
      "hosts/common/optional/services/netbird-client.nix"

      # Containers
      "hosts/common/optional/containers/step-ca.nix"
      # "hosts/common/optional/containers/immich.nix"
      # TODO: problems with declarative-jellyfin
      # "hosts/common/optional/containers/jellyfin.nix"
      "hosts/common/optional/containers/kanidm.nix"
      # "hosts/common/optional/containers/sonarr.nix"
      # "hosts/common/optional/containers/radarr.nix"
      # "hosts/common/optional/containers/prowlarr.nix"
      # "hosts/common/optional/containers/qbittorrent.nix"
      # "hosts/common/optional/containers/jellyseer.nix"
      "hosts/common/optional/containers/bazarr.nix"
      # "hosts/common/optional/containers/monitoring.nix"

      # HAProxy
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

  # Shared GPU configuration
  # ls -la /dev/dri/by-path/
  hostSpec.gpu = lib.mkDefault {
    renderDevice = "/dev/dri/by-path/pci-0000:00:02.0-render";
    cardDevice = "/dev/dri/by-path/pci-0000:00:02.0-card";
  };

  hostSpec.isServer = true;

  custom.services.jellyfin = {
    enable = true;
    secretsFile = "${builtins.toString inputs.nix-secrets}/sops/${config.hostSpec.hostName}.yaml";
  };
  custom.services.immich.enable = true;
  custom.services.sonarr.enable = true;
  custom.services.qbittorrent.enable = true;
  custom.services.prowlarr.enable = true;
  custom.services.radarr.enable = true;
  custom.services.jellyseerr.enable = true;
  custom.services.cross-seed.enable = true;
  custom.services.netbird = {
    enable = true;
    dashboard.enable = true;
    setupKeyFile = config.sops.secrets."netbird/setup-key".path;
    staticIPs = {
      "${config.hostSpec.hostName}" = "100.75.0.5";
    };
    nameservers = [
      {
        name = "${config.hostSpec.hostName}-unbound";
        ip = "100.75.0.5";
        primary = false;
        domains = [ "." ];
        searchDomains = false;
      }
    ];
  };

  custom.services.netbird-client = {
    enable = true;
    managementURL = "https://netbird.${inputs.nix-secrets.nas0.domain}:443";
    setupKeyFile = config.sops.secrets."netbird/setup-key".path;
    disableDNS = true;
  };

  nixpkgs.overlays = [
    inputs.self.outputs.overlays.immich-openvino
    inputs.self.outputs.overlays.quic-kernel-module-overlay
    inputs.self.outputs.overlays.samba-overlay
  ];
}
