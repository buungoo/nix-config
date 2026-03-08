{
  symlinkJoin,
  fetchFromGitHub,
  writeScriptBin,
  makeWrapper,
  coreutils,
  gnugrep,
  gawk,
  gnused,
  snapraid,
  snapper,
}:
let
  name = "snapraid-btrfs";
  deps = [
    coreutils
    gnugrep
    gawk
    gnused
    snapraid
    snapper
  ];
  script =
    (writeScriptBin name (
      builtins.readFile (
        # Using D34DC3N73R fork for snapper 0.11.0+ support
        (fetchFromGitHub {
          owner = "D34DC3N73R";
          repo = "snapraid-btrfs";
          rev = "a43e9a40773772b881b1450edfef28c9937f5f27";
          sha256 = "sha256-zOFc1/H2hgcZMeGUnLvuWL+SFvE5kvekm0F/dvhakWI=";
        })
        + "/snapraid-btrfs"
      )
    )).overrideAttrs
      (old: {
        buildCommand = "${old.buildCommand}\n patchShebangs $out";
      });
in
symlinkJoin {
  inherit name;
  paths = [ script ] ++ deps;
  buildInputs = [ makeWrapper ];
  postBuild = "wrapProgram $out/bin/${name} --set PATH $out/bin";
}
