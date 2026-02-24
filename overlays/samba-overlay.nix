final: prev: {
  samba = prev.samba.overrideAttrs (oldAttrs: rec {
    version = "4.23.5";

    src = prev.fetchurl {
      url = "mirror://samba/samba/samba-${version}.tar.gz";
      hash = "sha256-WTpD3dDVeQIjffp2iI97Ast/x3RxETacsx4SbbSDa58=";
    };

    # Keep the essential patches from the original package
    # Filter out version-specific patches that may not apply
    patches = builtins.filter (
      p:
      builtins.match ".*no-persistent-install.*" (builtins.baseNameOf p) != null
      || builtins.match ".*fix-makeflags-parsing.*" (builtins.baseNameOf p) != null
    ) (oldAttrs.patches or [ ]);
  });

  # Ensure KIO SMB worker uses the overlaid samba with QUIC support
  kdePackages = prev.kdePackages // {
    kio-extras = prev.kdePackages.kio-extras.override {
      samba = final.samba;
    };
  };
}
