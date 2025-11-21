{ pkgs, hostSpec, lib, ... }:
{
  # Sol - Open source, fast macOS launcher with fuzzy finding
  # https://github.com/ospfranco/sol
  home.packages = lib.optionals hostSpec.isDarwin [
    pkgs.brewCasks.sol
  ];
}
