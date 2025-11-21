# IMPORTANT: This is used by NixOS and nix-darwin so options must exist in both!
{
  inputs,
  outputs,
  config,
  lib,
  pkgs,
  isDarwin ? false,
  ...
}:
let
  platform = if isDarwin then "darwin" else "nixos";
  platformModules = "${platform}Modules";
in
{
  imports = lib.flatten [
    inputs.home-manager.${platformModules}.home-manager
    inputs.sops-nix.${platformModules}.sops

    (map lib.custom.relativeToRoot [
      "modules/common"
      "hosts/common/core/${platform}.nix"
      "hosts/common/core/sops-${platform}.nix"
    ])
  ];

  # Time and locale
  time.timeZone = lib.mkDefault "Europe/Stockholm";

  networking.hostName = config.hostSpec.hostName;

  # System-wide packages that should be on ALL systems
  environment.systemPackages = with pkgs; [
    openssh
    git
    tree
    neovim
    just
  ];

  # Force home-manager to use global packages
  home-manager.useGlobalPkgs = true;
  # If there is a conflict file that is backed up, use this extension
  home-manager.backupFileExtension = "bk";

  # Configure Home Manager for each user by mapping over hostSpec.users
  home-manager.extraSpecialArgs = {
    inherit pkgs inputs;
    hostSpec = config.hostSpec;
  };

  home-manager.users = lib.mapAttrs (userName: userVars: {
    imports = [
      (lib.custom.relativeToRoot "home/${userName}/${config.hostSpec.hostName}")
      (lib.custom.relativeToRoot "home/common/core/default.nix")
    ];
    _module.args = {
      inherit userName userVars; # Pass these to HM config
    };
  }) config.hostSpec.users;

  # ========== Overlays ==========
  nixpkgs = {
    overlays = [
      outputs.overlays.default
    ];
    config = {
      allowUnfree = true;
    };
  };

  # ========== Nix Nix Nix ==========
  nix = {
    # This will add each flake input as a registry
    # To make nix3 commands consistent with your flake
    registry = lib.mapAttrs (_: value: { flake = value; }) inputs;

    # This will add your inputs to the system's legacy channels
    # Making legacy nix commands consistent as well, awesome!
    nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry;

    settings = {
      # See https://jackson.dev/post/nix-reasonable-defaults/
      connect-timeout = 5;
      log-lines = 25;
      min-free = 128000000; # 128MB
      max-free = 1000000000; # 1GB

      # Deduplicate and optimize nix store
      # Note: auto-optimise-store removed - use nix.optimise.automatic in platform-specific config
      warn-dirty = false;

      allow-import-from-derivation = true;

      experimental-features = [
        "nix-command"
        "flakes"
      ];
    };
  };

  # ========== Basic Shell Enablement ==========
  programs.zsh = {
    enable = true;
    enableCompletion = true;
  };
}
