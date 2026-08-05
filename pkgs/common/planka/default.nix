{
  lib,
  stdenv,
  fetchFromGitHub,
  buildNpmPackage,
  nodejs_22,
  python3,
  pkg-config,
  postgresql,
  makeWrapper,
  bash,
  autoPatchelfHook,
  glibc,
  squid,
}:

let
  version = "2.1.1";

  src = fetchFromGitHub {
    owner = "plankanban";
    repo = "planka";
    rev = version;
    hash = "sha256-NuAdZS2PDRKiNbqvE6Gwr1DMIUOYeKstOlX5UeF9sa4=";
  };

  # Python interpreter with apprise for runtime notifications.
  # The server's send-notifications.js spawns `<appPath>/.venv/bin/python` —
  # we symlink this interpreter into that location during assembly.
  pythonEnv = python3.withPackages (ps: [ ps.apprise ]);

  server = buildNpmPackage {
    pname = "planka-server";
    inherit version;
    src = "${src}/server";

    nodejs = nodejs_22;

    npmDepsHash = "sha256-wyXrZR9YNTTMFrQMiERapp4RgPBjr9syWLvWligZ7hI=";

    # Server's postinstall is `patch-package && npm run setup-python`. The
    # patch-package step is critical (Planka patches sails.io.js + sails +
    # waterline for socket.io v4 compatibility, etc.). The setup-python step
    # creates a venv via pip which fails in the sandbox. Replace the script
    # with just `patch-package` so patches still get applied; we provide
    # python externally via the wrapper.
    postPatch = ''
      ${nodejs_22}/bin/node -e '
        const fs = require("fs");
        const p = JSON.parse(fs.readFileSync("package.json"));
        if (p.scripts.postinstall && p.scripts.postinstall.includes("patch-package")) {
          p.scripts.postinstall = "patch-package";
        } else {
          delete p.scripts.postinstall;
        }
        delete p.scripts.prepare;
        fs.writeFileSync("package.json", JSON.stringify(p, null, 2));
      '
    '';

    nativeBuildInputs = [
      python3
      pkg-config
      autoPatchelfHook
    ];

    # Provide libs for autoPatchelfHook to fix the prebuilt sharp binary
    # (@img/sharp-libvips-linux-x64) at install time. We deliberately do NOT
    # set SHARP_FORCE_GLOBAL_LIBVIPS because that forces sharp to compile
    # from source via node-gyp, which requires node-gyp as a Node module —
    # painful to provide with buildNpmPackage. The npm-shipped prebuilt is
    # simpler once patchelf'd onto NixOS.
    buildInputs = [
      glibc
      stdenv.cc.cc.lib
      postgresql.lib
    ];

    # Strip musl variants of bcrypt/sharp before autoPatchelfHook runs.
    # Otherwise patchelf adds both `sharp-libvips-linux-x64/lib` and
    # `sharp-libvips-linuxmusl-x64/lib` to sharp's RPATH; the dynamic loader
    # finds the musl libvips first, which NEEDs libc.musl-x86_64.so.1, and
    # dlopen fails at runtime with ERR_DLOPEN_FAILED.
    preFixup = ''
      rm -rf $out/share/planka/node_modules/@img/sharp-linuxmusl-x64
      rm -rf $out/share/planka/node_modules/@img/sharp-libvips-linuxmusl-x64
      rm -f $out/share/planka/node_modules/bcrypt/prebuilds/linux-x64/bcrypt.musl.node
    '';

    npmBuildScript = "build";

    installPhase = ''
      runHook preInstall
      mkdir -p $out/share/planka
      cp -r dist/. $out/share/planka/
      cp -r node_modules $out/share/planka/node_modules
      # start.sh lives in source root, not dist
      cp start.sh $out/share/planka/start.sh
      chmod +x $out/share/planka/start.sh
      runHook postInstall
    '';

    dontNpmPrune = false;
  };

  client = buildNpmPackage {
    pname = "planka-client";
    inherit version;
    src = "${src}/client";

    nodejs = nodejs_22;

    npmDepsHash = "sha256-UcLfObgDNsfUMvkSzYYrznzScbKZjgsXJnLl07fBsfw=";

    # Client's postinstall is just `patch-package` — keep it. Patches include
    # sails.io.js socket.io v4 compatibility shim (without which the socket
    # client sends events the server can't parse).
    postPatch = ''
      ${nodejs_22}/bin/node -e '
        const fs = require("fs");
        const p = JSON.parse(fs.readFileSync("package.json"));
        delete p.scripts.prepare;
        fs.writeFileSync("package.json", JSON.stringify(p, null, 2));
      '
    '';

    # Matches Dockerfile stage 2.
    env = {
      INDEX_FORMAT = "ejs";
      DISABLE_ESLINT_PLUGIN = "true";
    };

    npmBuildScript = "build";

    nativeBuildInputs = [
      autoPatchelfHook
    ];

    buildInputs = [
      glibc
      stdenv.cc.cc.lib
    ];

    # sass-embedded ships a prebuilt dart binary that vite invokes during build.
    # autoPatchelfHook runs in fixupPhase (too late) — patch it ourselves now.
    preBuild = ''
      for dartBin in $(find node_modules/sass-embedded* -name dart -type f 2>/dev/null); do
        patchelf \
          --set-interpreter ${stdenv.cc.bintools.dynamicLinker} \
          --set-rpath "${lib.makeLibraryPath [ glibc stdenv.cc.cc.lib ]}" \
          "$dartBin"
      done
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r dist/. $out/
      runHook postInstall
    '';
  };

in
stdenv.mkDerivation {
  pname = "planka";
  inherit version;

  dontUnpack = true;
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/planka $out/bin

    # Server bundle (dist + node_modules + start.sh)
    cp -r ${server}/share/planka/. $out/share/planka/
    chmod -R u+w $out/share/planka

    # Client bundle as `public/`, with index.ejs moved to `views/` (mirrors Dockerfile)
    mkdir -p $out/share/planka/public $out/share/planka/views
    cp -r ${client}/. $out/share/planka/public/
    chmod -R u+w $out/share/planka/public
    if [ -f $out/share/planka/public/index.ejs ]; then
      mv $out/share/planka/public/index.ejs $out/share/planka/views/index.ejs
    fi

    # Provide python at the path the server expects: .venv/bin/python
    mkdir -p $out/share/planka/.venv/bin
    ln -s ${pythonEnv}/bin/python3 $out/share/planka/.venv/bin/python

    # Top-level launcher. start.sh launches an optional internal squid for
    # outgoing-traffic filtering if OUTGOING_BLOCKED_/ALLOWED_ env vars are
    # set — keep squid in PATH so that feature works opt-in.
    makeWrapper ${bash}/bin/bash $out/bin/planka \
      --add-flags "$out/share/planka/start.sh" \
      --prefix PATH : ${lib.makeBinPath [ nodejs_22 pythonEnv bash squid ]} \
      --chdir $out/share/planka

    runHook postInstall
  '';

  passthru = {
    inherit server client pythonEnv;
  };

  meta = with lib; {
    description = "Kanban-style project management board";
    homepage = "https://planka.app";
    license = licenses.agpl3Only;
    platforms = platforms.linux;
    mainProgram = "planka";
  };
}
