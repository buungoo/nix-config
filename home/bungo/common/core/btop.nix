{
  pkgs,
  lib,
  osConfig ? {},
  ...
}:
{
  programs.btop = {
    enable = true;
    package = pkgs.btop.override {
      cudaSupport = builtins.elem "nvidia" (osConfig.services.xserver.videoDrivers or []);
    };
    settings = {
      vim_keys = true;
      shown_boxes = "cpu mem net proc gpu0";
    };
  };
}
