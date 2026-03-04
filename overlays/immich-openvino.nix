# Overlay to enable OpenVINO (Intel GPU acceleration) for Immich Machine Learning
# Based on ongoing discussion in nixpkgs: https://github.com/NixOS/nixpkgs/issues/457288
final: prev: {
  # Override onnxruntime (C++) to add OpenVINO support for Intel iGPUs (N100).
  onnxruntime = prev.onnxruntime.overrideAttrs (oldAttrs: {
    buildInputs = (oldAttrs.buildInputs or [ ]) ++ [
      final.openvino
    ];

    nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [
      final.patchelf
    ];

    cmakeFlags = (oldAttrs.cmakeFlags or [ ]) ++ [
      (final.lib.cmakeBool "onnxruntime_USE_OPENVINO" true)
      (final.lib.cmakeFeature "OpenVINO_DIR" "${final.openvino}/runtime/cmake")
    ];

    # PostFixup RPATH addition
    postFixup = (oldAttrs.postFixup or "") + ''
      patchelf --add-rpath "${final.openvino}/runtime/lib/intel64" "${if oldAttrs ? __structuredAttrs && oldAttrs.__structuredAttrs then "$" + "{!outputLib}" else "$out"}/lib/libonnxruntime_providers_openvino.so"
    '';

    # Disable checks as provider shared libs aren't available during the test phase
    doCheck = false;
  });

  # Override the Python onnxruntime wrapper to include OpenVINO libs.
  pythonPackagesExtensions = (prev.pythonPackagesExtensions or [ ]) ++ [
    (pyFinal: pyPrev: {
      onnxruntime = pyPrev.onnxruntime.overrideAttrs (oldAttrs: {
        buildInputs = (oldAttrs.buildInputs or [ ]) ++ [
          final.openvino
        ];
      });
    })
  ];

  # Ensure the standalone machine-learning package has tests disabled and use correct python.
  immich-machine-learning = (prev.immich-machine-learning.override {
    python3 = final.python3;
  }).overrideAttrs (_: {
    doCheck = false;
    nativeCheckInputs = [ ];
    installCheckPhase = "true";
    checkPhase = "true";
    pytestCheckPhase = "true";
  });

  # Override the main immich package
  immich = (prev.immich.override {
    python3 = final.python3;
    immich-machine-learning = final.immich-machine-learning;
  }).overrideAttrs (old: {
    passthru = old.passthru // {
      # The NixOS service specifically uses pkgs.immich.machine-learning.
      # We point it to our already-overridden version.
      machine-learning = final.immich-machine-learning.override {
        immich = final.immich;
      };
    };
  });
}
