{
  description = "Bungo's Nix Configuration";
  outputs =
    {
      self,
      nixpkgs,
      nix-darwin,
      ...
    }@inputs:
    let
      inherit (self) outputs;

      # ========= Architectures =========
      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-darwin"
      ];

      # ========== Extend lib with lib.custom ==========
      lib = nixpkgs.lib.extend (
        self: super: { custom = import ./lib { inherit (nixpkgs) lib inputs; }; }
      );
    in
    {
      # ========= Overlays =========
      # Custom modifications/overrides to upstream packages
      overlays = import ./overlays { inherit inputs; };

      # ========= Host Configurations =========
      nixosConfigurations = builtins.listToAttrs (
        map (host: {
          name = host;
          value = nixpkgs.lib.nixosSystem {
            specialArgs = {
              inherit inputs outputs lib;
              isDarwin = false;
            };
            modules = [ ./hosts/nixos/${host} ];
          };
        }) (builtins.attrNames (builtins.readDir ./hosts/nixos))
      );

      # ========= Darwin Configurations =========
      darwinConfigurations = builtins.listToAttrs (
        map (host: {
          name = host;
          value = nix-darwin.lib.darwinSystem {
            specialArgs = {
              inherit inputs outputs lib;
              isDarwin = true;
            };
            modules = [ ./hosts/darwin/${host} ];
          };
        }) (builtins.attrNames (builtins.readDir ./hosts/darwin))
      );

      # ========= Packages =========
      # Expose custom packages
      /*
        NOTE: This is only for exposing packages exterally; ie, `nix build .#packages.x86_64-linux.cd-gitroot`
        For internal use, these packages are added through the default overlay in `overlays/default.nix`
      */
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ self.overlays.default ];
          };
        in
        nixpkgs.lib.packagesFromDirectoryRecursive {
          callPackage = nixpkgs.lib.callPackageWith pkgs;
          directory = ./pkgs/common;
        }
      );

      # ========= Formatting =========
      # Nix formatter with treefmt wrapper for recursive formatting
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);

      # ========= DevShell =========
      # Custom shell for bootstrapping on new hosts, modifying nix-config, and secrets management
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              sops
              age
              git
              nixfmt-rfc-style
            ];
          };
        }
      );
    };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # ========= Utilities =========
    # Secrets management
    sops-nix = {
      url = "github:mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Declarative disk partitioning
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # nix-darwin for macOS support
    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # ========= Applications =========
    # Ghostty terminal emulator (using flake because aarch64-darwin is not yet in nixpkgs)
    ghostty = {
      url = "github:ghostty-org/ghostty";
    };
    # nixCats neovim configuration
    nvim-config = {
      url = "github:buungoo/nvim-config";
    };
    # brew-nix for macOS applications (Homebrew Casks as Nix packages)
    brew-nix = {
      url = "github:BatteredBunny/brew-nix";
      inputs.brew-api.follows = "brew-api";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    brew-api = {
      url = "github:BatteredBunny/brew-api";
      flake = false;
    };

    # ========= Personal Repositories =========
    # Private secrets repo (using local path instead of SSH to avoid daemon issues)
    nix-secrets = {
      url = "git+file:///Users/bungo/.nixos/nix-secrets";
      inputs = { };
    };
    # Declarative Jellyfin
    declarative-jellyfin = {
      url = "github:Sveske-Juice/declarative-jellyfin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
