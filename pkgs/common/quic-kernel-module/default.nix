{ lib, stdenv, fetchFromGitHub, kernel, autoconf, automake, libtool, pkg-config, gnutls, python3 }:

stdenv.mkDerivation rec {
  pname = "quic-kernel-module";
  version = "unstable-2025-12-17";

  src = fetchFromGitHub {
    owner = "lxin";
    repo = "quic";
    rev = "0b830fb6e5bfd30024c596a3016243f1704fe646";
    hash = "sha256-IDcxTmtI6fV3zrQDCVYt9S1E+KQK3cJLEYrFsRwsEBc=";
  };

  nativeBuildInputs = [ autoconf automake libtool pkg-config python3 ] ++ kernel.moduleBuildDependencies;
  buildInputs = [ gnutls ];

  preConfigure = ''
    ./autogen.sh

    # Configure script expects kernel in /lib/modules/$(uname -r)
    # Create this structure and symlink to our kernel
    mkdir -p /build/lib/modules/${kernel.modDirVersion}
    ln -sf ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build /build/lib/modules/${kernel.modDirVersion}/build

    # Patch configure script to look in /build instead of /lib
    sed -i 's|kernel="/lib/modules|kernel="/build/lib/modules|g' configure
  '';

  configureFlags = [
    "--prefix=${placeholder "out"}"
  ];

  # Don't use kernel.makeFlags for top-level build as it includes both userspace and kernel modules
  # The modules subdirectory Makefile will handle kernel-specific flags
  makeFlags = [ ];

  preInstall = ''
    # Create the include directory
    mkdir -p $out/include/linux

    # Fix the install path for headers - redirect from /usr/include to $out/include
    # Also skip depmod as we don't need it in NixOS builds
    substituteInPlace modules/Makefile \
      --replace '/usr/include/linux' "$out/include/linux" \
      --replace 'depmod -a' 'true'
  '';

  installFlags = [
    "INSTALL_MOD_PATH=${placeholder "out"}"
    "KERNEL_EXTRA=${placeholder "out"}/lib/modules/${kernel.modDirVersion}/extra"
  ];

  # Modules are installed directly to the correct location via KERNEL_EXTRA installFlag
  # No post-processing needed

  meta = with lib; {
    description = "QUIC kernel module for Linux";
    homepage = "https://github.com/lxin/quic";
    license = licenses.gpl2;
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
