final: prev: {
  samba = prev.samba.overrideAttrs (oldAttrs: rec {
    version = "4.23.6";

    src = prev.fetchurl {
      url = "mirror://samba/samba/samba-${version}.tar.gz";
      hash = "sha256-49q9i15C3Jdmn6D67wMlEKlOSWtY9wZwguUDbYjw5wI=";
    };

    # Keep the essential patches from the original package
    # Filter out version-specific patches that may not apply
    patches = builtins.filter (
      p:
      builtins.match ".*no-persistent-install.*" (builtins.baseNameOf p) != null
    ) (oldAttrs.patches or [ ]);
  });

  # Ensure KIO SMB worker uses the overlaid samba with QUIC support
  kdePackages = prev.kdePackages // {
    kio-extras = prev.kdePackages.kio-extras.override {
      samba = final.samba;
    };
  };
}
