{ pkgs, ... }:
{
  home.packages = [
    (pkgs.freecad.overrideAttrs (old: {
      postFixup = (old.postFixup or "") + ''
        wrapProgram $out/bin/FreeCAD \
          --set QT_QPA_PLATFORM xcb
        wrapProgram $out/bin/FreeCADCmd \
          --set QT_QPA_PLATFORM xcb
      '';
    }))
  ];
}
