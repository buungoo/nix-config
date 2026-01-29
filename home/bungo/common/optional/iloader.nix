{ pkgs, hostSpec, lib, ... }:
{
  home.packages = lib.optionals hostSpec.isDarwin [
    pkgs.iloader
  ];
}
