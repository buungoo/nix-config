final: prev: {
  # Add QUIC kernel module to all kernel package sets
  linuxPackagesFor = kernel:
    (prev.linuxPackagesFor kernel).extend (
      lpFinal: lpPrev: {
        quic-kernel-module = lpFinal.callPackage ../pkgs/common/quic-kernel-module {
          kernel = lpFinal.kernel;
        };
      }
    );
}
