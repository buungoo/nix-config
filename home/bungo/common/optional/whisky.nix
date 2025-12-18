{ pkgs, ... }:

{
  home.packages = with pkgs; [
    whisky
  ];
}
