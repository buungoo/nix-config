{
  pkgs,
  hostSpec,
  ...
}:
let
  orca-slicer-wrapped = pkgs.symlinkJoin {
    name = "orca-slicer";
    paths = [ pkgs.orca-slicer ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/orca-slicer \
        --set __GLX_VENDOR_LIBRARY_NAME mesa \
        --set __EGL_VENDOR_LIBRARY_FILENAMES /run/opengl-driver/share/glvnd/egl_vendor.d/50_mesa.json \
        --set MESA_LOADER_DRIVER_OVERRIDE zink \
        --set WEBKIT_DISABLE_COMPOSITING_MODE 1 \
        --set WEBKIT_DISABLE_DMABUF_RENDERER 1
    '';
  };
in
{
  home.packages = [
    (if hostSpec.isDarwin then pkgs.brewCasks.orca-slicer else orca-slicer-wrapped)
  ];
}
