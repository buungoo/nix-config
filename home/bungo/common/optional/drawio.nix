{
  pkgs,
  ...
}:
{
  home.packages = [
    # inputs.nixcats.packages.${pkgs.stdenv.hostPlatform.system}.svim
    pkgs.drawio
  ];
}
