{
  pkgs,
  inputs,
  ...
}:
{
  home.packages = [
    # inputs.nvim-config.packages.${pkgs.stdenv.hostPlatform.system}.default
    inputs.nixcats.packages.${pkgs.stdenv.hostPlatform.system}.nvim
    # inputs.nixcats.packages.${pkgs.stdenv.hostPlatform.system}.svim
  ];
}
