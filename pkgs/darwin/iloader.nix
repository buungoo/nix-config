{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
}:

stdenvNoCC.mkDerivation rec {
  pname = "iloader";
  version = "1.1.6";

  src = fetchurl {
    url = "https://github.com/nab138/iloader/releases/download/v${version}/iloader-darwin-universal.app.tar.gz";
    hash = "sha256-OQa5cQx2KIh1op3wMH0I8v9vXOq6PeF00Z0NQRL823s=";
  };

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/Applications"
    cp -R iloader.app "$out/Applications/"
    runHook postInstall
  '';

  meta = with lib; {
    description = "iOS sideloading tool for SideStore";
    homepage = "https://github.com/nab138/iloader";
    license = licenses.unfree;
    platforms = platforms.darwin;
    maintainers = [ ];
  };
}
