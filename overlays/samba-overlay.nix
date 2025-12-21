final: prev: {
  samba = prev.samba.overrideAttrs (oldAttrs: rec {
    version = "4.23.4";

    src = prev.fetchurl {
      url = "mirror://samba/samba/samba-${version}.tar.gz";
      hash = "sha256-r0KdB4qG8c4W0NHs7jXEKjYQeQtHuERo8xKEqMQGAUA=";
    };

    # Keep the essential patches from the original package
    # Filter out version-specific patches that may not apply
    patches = builtins.filter (p:
      builtins.match ".*no-persistent-install.*" (builtins.baseNameOf p) != null ||
      builtins.match ".*fix-makeflags-parsing.*" (builtins.baseNameOf p) != null
    ) (oldAttrs.patches or [ ]);
  });
}
