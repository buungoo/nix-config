{
  pkgs,
  hostSpec,
  ...
}:
let
  features = [
    "AcceleratedVideoEncoder"
    "AcceleratedVideoDecodeLinuxZeroCopyGL"
    "AcceleratedVideoDecodeLinuxGL"
    "VaapiIgnoreDriverChecks"
    "VaapiOnNvidiaGPUs"
  ];
  vivaldi-wrapped = pkgs.vivaldi.override {
    vivaldi-ffmpeg-codecs = pkgs.vivaldi-ffmpeg-codecs;
    proprietaryCodecs = true;
    commandLineArgs = builtins.concatStringsSep " " [
      "--enable-features=${builtins.concatStringsSep "," features}"
      "--ignore-gpu-blocklist"
    ];
  };
in
{
  home.packages = [
    (if hostSpec.isDarwin then pkgs.brewCasks.vivaldi else vivaldi-wrapped)
  ];
}
