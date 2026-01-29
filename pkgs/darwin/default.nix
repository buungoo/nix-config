# Darwin-specific packages
{ pkgs }:
{
  iloader = pkgs.callPackage ./iloader.nix { };
}
