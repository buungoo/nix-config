{ pkgs, hostSpec, lib, ... }:
{
  # Commander One - dual-pane file manager (macOS only)
  home.packages = lib.optionals hostSpec.isDarwin [
    # Override with correct hash (brew-nix had empty hash)
    (pkgs.brewCasks.commander-one.overrideAttrs (old: {
      src = pkgs.fetchurl {
        inherit (old.src) url;
        sha256 = "sha256-kHktV4Fy+hUUlHMteqdir8nBKN18snauTCgV1xe5ltA=";
      };
    }))
  ];
}
