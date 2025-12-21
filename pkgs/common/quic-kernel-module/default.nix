{ lib, stdenv, fetchFromGitHub, kernel, autoconf, automake, libtool, pkg-config, gnutls }:

stdenv.mkDerivation rec {
  pname = "quic-kernel-module";
  version = "unstable-2024-12-20";

  src = fetchFromGitHub {
    owner = "lxin";
    repo = "quic";
    rev = "73c11f7c9f6f4f6e20e67ee51d80db5e5e1c9a04";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  nativeBuildInputs = [ autoconf automake libtool pkg-config ] ++ kernel.moduleBuildDependencies;
  buildInputs = [ gnutls ];

  preConfigure = ''
    ./autogen.sh
  '';

  configureFlags = [
    "--prefix=${placeholder "out"}"
  ];

  makeFlags = kernel.makeFlags;

  # Override the kernel build directory
  preBuild = ''
    export KERNELDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build
  '';

  installFlags = [
    "INSTALL_MOD_PATH=${placeholder "out"}"
  ];

  meta = with lib; {
    description = "QUIC kernel module for Linux";
    homepage = "https://github.com/lxin/quic";
    license = licenses.gpl2;
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
