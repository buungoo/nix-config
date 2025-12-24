final: prev: {
  brewCasks = prev.brewCasks or { } // {
    vivaldi = prev.brewCasks.vivaldi.overrideAttrs (old: {
      # Fix unpackPhase for .tar.xz files
      # brew-nix's default uses 7zz which only extracts the .xz layer
      # We need to extract both .xz and .tar
      unpackPhase = ''
        # Try standard methods first
        undmg $src || unzip $src || {
          # For .tar.xz files, extract in two stages
          if [[ $src == *.tar.xz ]]; then
            7zz x $src
            tar xf *.tar
            rm *.tar
          else
            7zz x -snld $src
          fi
        }
      '';
    });
  };
}
