{
  pkgs,
  inputs,
  ...
}:
{
  # home.packages = [
  #   inputs.vacuumtube.packages.${pkgs.stdenv.hostPlatform.system}.vacuumtube
  # ];

  imports = [
    inputs.vacuumtube.homeManagerModules.vacuumtube
  ];

  programs.vacuumtube = {
    enable = true;
    enableFeatures = [
      "AcceleratedVideoDecodeLinuxZeroCopyGL"
      "AcceleratedVideoDecodeLinuxGL"
      "VaapiIgnoreDriverChecks"
      "VaapiOnNvidiaGPUs"
    ];
    electronFlags = [
      "--ignore-gpu-blocklist"
    ];
  };
}
