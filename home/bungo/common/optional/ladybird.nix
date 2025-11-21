{ pkgs, ... }:
{
  # NOTE: Ladybird is marked broken on Darwin (missing OpenGL/framework support)
  # https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/la/ladybird/package.nix
  home.packages = [
    pkgs.ladybird
  ];
}
