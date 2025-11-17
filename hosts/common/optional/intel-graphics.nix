{ pkgs, ... }:
{
  # Enable Intel graphics hardware acceleration
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      libva-vdpau-driver
      intel-compute-runtime # OpenCL filter support (hardware tonemapping and subtitle burn-in)
      vpl-gpu-rt # QSV on 11th gen or newer
      intel-ocl # OpenCL support
    ];
  };

  # https://wiki.nixos.org/wiki/Jellyfin
  # Enable vaapi on OS-level
  nixpkgs.config.packageOverrides = pkgs: {
    intel-vaapi-driver = pkgs.intel-vaapi-driver.override {
      enableHybridCodec = true;
    };
  };

  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "iHD";
  };

  # Enable sensor detection
  hardware.sensor.iio.enable = true;

  # Intel GPU tools and utilities
  environment.systemPackages = with pkgs; [
    intel-gpu-tools
    libva-utils
  ];
}
