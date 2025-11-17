# Custom packages
{ pkgs }:
{
  step-ca-enroll = pkgs.callPackage ./step-ca-enroll-go { };
  snapraid-btrfs = pkgs.callPackage ./snapraid-btrfs { };
  snapraid-btrfs-runner = pkgs.callPackage ./snapraid-btrfs-runner {
    inherit (pkgs) snapraid-btrfs;
  };
}
