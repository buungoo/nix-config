{
  description = "Minimal NixOS configuration for bootstrapping established hosts";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    disko.url = "github:nix-community/disko";
  };

  outputs =
    {
      self,
      nixpkgs,
      ...
    }@inputs:
    let
      inherit (self) outputs;

      # Custom packages overlay
      pkgs = import nixpkgs {
        system = "x86_64-linux";
        config.allowUnfree = true;
        overlays = [
          (final: _prev: import ../pkgs/common { pkgs = final; })
        ];
      };

      minimalSpecialArgs = {
        inherit inputs outputs pkgs;
        lib = nixpkgs.lib.extend (self: super: {
          custom = import ../lib {
            inherit inputs;
            lib = nixpkgs.lib;
          };
        });
      };

      # Helper function to create a minimal config for bootstrapping
      # name: hostname
      # diskConfig: path to disk configuration file relative to ../hosts/nixos/${name}/
      #   - Typically "btrfs-storage.nix" to use the host's actual disk layout
      newConfig =
        name: diskConfig:
        nixpkgs.lib.nixosSystem {
          inherit pkgs;
          system = "x86_64-linux";
          specialArgs = minimalSpecialArgs;
          modules = [
            inputs.disko.nixosModules.disko
            ../hosts/nixos/${name}/${diskConfig}
            ./minimal-configuration.nix
            ../hosts/nixos/${name}/hardware-configuration.nix

            { networking.hostName = name; }
          ];
        };
    in
    {
      # Expose ISO as a package for easier building
      packages.x86_64-linux.iso = (nixpkgs.lib.nixosSystem {
        inherit pkgs;
        system = "x86_64-linux";
        specialArgs = minimalSpecialArgs;
        modules = [ ./iso.nix ];
      }).config.system.build.isoImage;

      nixosConfigurations = {
        # Custom installation ISO
        iso = nixpkgs.lib.nixosSystem {
          inherit pkgs;
          system = "x86_64-linux";
          specialArgs = minimalSpecialArgs;
          modules = [ ./iso.nix ];
        };

        # Bootstrap configurations for established hosts
        # host = newConfig "hostname" "disk-config-file.nix"
        #
        # disk-config-file.nix should be a path relative to ../hosts/nixos/<hostname>/
        # Typically this is "btrfs-storage.nix" which contains the actual disk layout

        # nas0 - uses actual disk layout from btrfs-storage.nix
        nas0 = newConfig "nas0" "btrfs-storage.nix";

        # nas1 - uses actual disk layout from btrfs-storage.nix
        nas1 = newConfig "nas1" "btrfs-storage.nix";

        # Add more hosts here as needed:
        # newhost = newConfig "newhost" "btrfs-storage.nix";
      };
    };
}
