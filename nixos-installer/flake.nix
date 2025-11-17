{
  description = "Minimal NixOS configuration for bootstrapping yano systems";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
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

      minimalSpecialArgs = {
        inherit inputs outputs;
        lib = nixpkgs.lib.extend (self: super: { custom = import ../lib { inherit (nixpkgs) lib; }; });
      };

      # Helper function to create a minimal config for bootstrapping
      # name: hostname
      # disk: device path (e.g., "/dev/sda")
      # swapSize: swap size in GiB (0 for no swap)
      # useLuks: whether to use LUKS encryption
      newConfig =
        name: disk: swapSize: useLuks:
        (
          let
            diskSpecPath =
              if useLuks then ../hosts/common/disks/btrfs-luks.nix else ../hosts/common/disks/btrfs-simple.nix;
          in
          nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = minimalSpecialArgs;
            modules = [
              inputs.disko.nixosModules.disko
              diskSpecPath
              {
                _module.args = {
                  inherit disk;
                  withSwap = swapSize > 0;
                  swapSize = builtins.toString swapSize;
                };
              }
              ./minimal-configuration.nix
              ../hosts/nixos/${name}/hardware-configuration.nix

              { networking.hostName = name; }
            ];
          }
        );
    in
    {
      nixosConfigurations = {
        # Example configurations:
        # host = newConfig "name" "disk" swapSize useLuks
        # Swap size is in GiB (0 for no swap)

        # nas0 (using simple template, not custom storage)
        nas0 = newConfig "nas0" "/dev/nvme0n1" 8 false;

        # Add more hosts here as needed:
        # newhost = newConfig "newhost" "/dev/sda" 16 true;
      };
    };
}
