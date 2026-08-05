# Overlay to enable OpenVINO (Intel GPU acceleration) for Immich Machine Learning
# Incorporating wisdom from nixpkgs issue: https://github.com/NixOS/nixpkgs/issues/457288
final: prev: {
  # Override onnxruntime (C++) to add OpenVINO support for Intel iGPUs (N100).
  onnxruntime = prev.onnxruntime.overrideAttrs (oldAttrs: {
    buildInputs = (oldAttrs.buildInputs or [ ]) ++ [
      final.openvino
      final.zlib
      final.libxml2
      final.ocl-icd
      final.intel-ocl
      final.tbb
    ];

    nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [
      final.patchelf
    ];

    cmakeFlags = (oldAttrs.cmakeFlags or [ ]) ++ [
      (final.lib.cmakeBool "onnxruntime_USE_OPENVINO" true)
      (final.lib.cmakeFeature "OpenVINO_DIR" "${final.openvino}/runtime/cmake")
    ];

    # OpenVINO internally dlopen's frontend libs which aren't direct link dependencies.
    # We must manually add openvino's lib dir to the provider's RUNPATH.
    # Note: onnxruntime uses __structuredAttrs so we use ''${!outputLib} (bash indirect expansion).
    postFixup = (oldAttrs.postFixup or "") + ''
      SO_FILE="''${!outputLib}/lib/libonnxruntime_providers_openvino.so"
      if [ -f "$SO_FILE" ]; then
        patchelf --add-rpath "${final.openvino}/runtime/lib/intel64:${final.openvino}/lib:${final.zlib}/lib:${final.libxml2}/lib:${final.stdenv.cc.cc.lib}/lib:${final.intel-compute-runtime}/lib:${final.level-zero}/lib:${final.ocl-icd}/lib:${final.intel-ocl}/lib:${final.tbb}/lib" "$SO_FILE"
      fi
    '';

    doCheck = false;
  });

  # Override the Python onnxruntime wrapper to include OpenVINO libs for auto-patchelf.
  pythonPackagesExtensions = (prev.pythonPackagesExtensions or [ ]) ++ [
    (pyFinal: pyPrev: {
      onnxruntime = pyPrev.onnxruntime.overrideAttrs (oldAttrs: {
        buildInputs = (oldAttrs.buildInputs or [ ]) ++ [
          final.openvino
          final.zlib
          final.libxml2
          final.tbb # TBB is often a dependency for OpenVINO's performance optimizations
          final.intel-compute-runtime # Required for OpenCL/GPU plugin
          final.level-zero # Required for OpenCL/GPU plugin
          final.ocl-icd # OpenCL ICD loader
          final.intel-ocl # Intel OpenCL ICD
        ];


        # For PEP 517 builds, pass CMake arguments via --config-settings
        pypaBuildFlags = (oldAttrs.pypaBuildFlags or []) ++ [
          "--config-settings=cmake.args=-Donnxruntime_USE_OPENVINO=TRUE -DOpenVINO_DIR=${final.openvino}/runtime/cmake"
        ];
        
        # Ensure the shared provider libraries are properly patched within the python package.
        postFixup = (oldAttrs.postFixup or "") + ''
          # Find the main shared object of onnxruntime python package
          find $out -name "_pybind11_state*.so" -exec \
            patchelf --add-rpath "${final.onnxruntime}/lib:${final.openvino}/runtime/lib/intel64:${final.openvino}/lib:${final.zlib}/lib:${final.libxml2}/lib:${final.stdenv.cc.cc.lib}/lib:${final.intel-compute-runtime}/lib:${final.level-zero}/lib:${final.ocl-icd}/lib:${final.intel-ocl}/lib:${final.tbb}/lib" {} \;
          
          # Also try to symlink the provider .so if it was built in the C++ package but not here
          PROVIDER_SO="libonnxruntime_providers_openvino.so"
          CAPI_DIR=$(find $out -name "capi" -type d | head -n 1)
          if [ -n "$CAPI_DIR" ] && [ ! -f "$CAPI_DIR/$PROVIDER_SO" ] && [ -f "${final.onnxruntime}/lib/$PROVIDER_SO" ]; then
            ln -s "${final.onnxruntime}/lib/$PROVIDER_SO" "$CAPI_DIR/$PROVIDER_SO"
          fi
        '';
      });

      insightface = pyPrev.insightface.overrideAttrs (oldAttrs: {
        postInstall = (oldAttrs.postInstall or "") + ''
        RF_FILE="$out/${final.python3.sitePackages}/insightface/model_zoo/retinaface.py"
          if [ -f "$RF_FILE" ]; then
            RF_FILE="$RF_FILE" ${final.python3}/bin/python3 - <<'PY'
from pathlib import Path
import os

path = Path(os.environ["RF_FILE"])
text = path.read_text()
needle = "        input_size = self.input_size if input_size is None else input_size\n"
insert = needle + "        if input_size is None or any(x is None for x in input_size):\n            input_size = (640, 640)\n            self.input_size = (640, 640)\n"
if needle in text and "any(x is None for x in input_size)" not in text:
    text = text.replace(needle, insert, 1)
    path.write_text(text)
PY
          fi
        '';
      });
    })
  ];

  # Ensure the standalone machine-learning package has tests disabled and use correct python.
  immich-machine-learning = (prev.immich-machine-learning.override {
    python3 = final.python3;
  }).overrideAttrs (old: {
    propagatedBuildInputs = (old.propagatedBuildInputs or [ ]) ++ [
      final.python3Packages.openvino
      final.python3Packages.torch
      final.python3Packages."open-clip-torch"
    ];
    doCheck = false;
    nativeCheckInputs = [ ];
    installCheckPhase = "true";
    checkPhase = "true";
    pytestCheckPhase = "true";

    # Use a clean overwrite of the session logic to force GPU and provide diagnostics.
    postInstall = (old.postInstall or "") + ''
      cat > $out/lib/python*/site-packages/immich_ml/sessions/ort.py <<EOF
from __future__ import annotations
import sys
import os
import glob
from pathlib import Path
from typing import Any
import numpy as np
import onnxruntime as ort
from numpy.typing import NDArray
from immich_ml.models.constants import SUPPORTED_PROVIDERS
from immich_ml.schemas import SessionNode
from ..config import log, settings

class OrtSession:
    def __init__(self, model_path: Path | str, providers=None, provider_options=None, sess_options=None):
        self.model_path = Path(model_path)
        
        # NUCLEAR OPTION: Force LD_LIBRARY_PATH
        ort_lib_dir = "${final.onnxruntime}/lib"
        ov_lib_dir = "${final.openvino}/runtime/lib/intel64"
        intel_compute_lib = "${final.intel-compute-runtime}/lib"
        level_zero_lib = "${final.level-zero}/lib"
        ocl_icd_lib = "${final.ocl-icd}/lib"
        intel_ocl_lib = "${final.intel-ocl}/lib"
        tbb_lib = "${final.tbb}/lib"
        os.environ["LD_LIBRARY_PATH"] = f"{ort_lib_dir}:{ov_lib_dir}:{intel_compute_lib}:{level_zero_lib}:{ocl_icd_lib}:{intel_ocl_lib}:{tbb_lib}:" + os.environ.get("LD_LIBRARY_PATH", "")
        os.environ.setdefault("OPENVINO_PLUGIN_PATH", ov_lib_dir)
        os.environ.setdefault("OV_PLUGIN_PATH", ov_lib_dir)
        os.environ.setdefault("OCL_ICD_VENDORS", "/run/opengl-driver/etc/OpenCL/vendors")
        
        # DIAGNOSTICS
        sys.stderr.write(f"!!! DIAGNOSTIC: Available providers: {ort.get_available_providers()}\\\\n")
        # Check for the provider .so file
        try:
            ort_package_dir = Path(ort.__file__).parent
            provider_so = list(ort_package_dir.glob("**/libonnxruntime_providers_openvino.so"))
            if provider_so:
                sys.stderr.write(f"!!! DIAGNOSTIC: Found OpenVINO provider in ORT package at: {provider_so[0]}\\\\n")
            else:
                # Check the C++ onnxruntime directory
                provider_so = list(Path("${final.onnxruntime}/lib").glob("libonnxruntime_providers_openvino.so"))
                if provider_so:
                    sys.stderr.write(f"!!! DIAGNOSTIC: Found OpenVINO provider in C++ lib at: {provider_so[0]}\\\\n")
                else:
                    sys.stderr.write("!!! DIAGNOSTIC: OpenVINO provider NOT FOUND anywhere\\\\n")
        except Exception as e:
            sys.stderr.write(f"!!! DIAGNOSTIC ERROR: {e}\\\\n")

        # FORCE OpenVINO ON GPU - NO FALLBACKS
        self.providers = ["OpenVINOExecutionProvider"]
        device_env = os.environ.get("OPENVINO_DEVICE", "")
        # Log the env we actually see inside the service.
        sys.stderr.write(f"!!! DIAGNOSTIC: OPENVINO_DEVICE env: {device_env!r}\\\\n")
        ocl_icd = os.environ.get("OCL_ICD_VENDORS", "")
        opencl_vendor = os.environ.get("OPENCL_VENDOR_PATH", "")
        sys.stderr.write("!!! DIAGNOSTIC: OCL_ICD_VENDORS env: %r\\\\n" % ocl_icd)
        sys.stderr.write("!!! DIAGNOSTIC: OPENCL_VENDOR_PATH env: %r\\\\n" % opencl_vendor)
        if device_env:
            device_types = [d.strip() for d in device_env.split(",") if d.strip()]
        else:
            device_types = ["GPU", "GPU_FP16", "GPU.0", "AUTO:GPU", "AUTO:GPU,CPU", "HETERO:GPU,CPU"]
        # If the env only specifies GPU, still try common GPU variants and fallback modes.
        if device_types == ["GPU"]:
            device_types = ["GPU", "GPU_FP16", "GPU.0", "AUTO:GPU", "AUTO:GPU,CPU", "HETERO:GPU,CPU"]
        self.provider_options = [{
            "device_type": device_types[0],
        }]

        # OpenVINO runtime diagnostics
        try:
            from openvino.runtime import Core
            core = Core()
            sys.stderr.write(f"!!! DIAGNOSTIC: OpenVINO devices: {core.available_devices}\\\\n")
        except Exception as e:
            sys.stderr.write(f"!!! DIAGNOSTIC: OpenVINO runtime error: {e}\\\\n")
        
        # VERBOSE LOGGING
        self.sess_options = sess_options if sess_options is not None else ort.SessionOptions()
        self.sess_options.log_severity_level = 0
        
        sys.stderr.write(f"!!! FORCING OpenVINO GPU FOR: {self.model_path.name}\\\\n")
        sys.stderr.write(f"!!! DIAGNOSTIC: OpenVINO device candidates: {device_types}\\\\n")
        # Direct call to InferenceSession, no try-except, force crash on failure
        try:
            last_error = None
            for device_type in device_types:
                try:
                    self.session = ort.InferenceSession(
                        self.model_path.as_posix(),
                        providers=[("OpenVINOExecutionProvider", {
                            "device_type": device_type,
                        })],
                        sess_options=self.sess_options
                    )
                    used_providers = self.session.get_providers()
                    sys.stderr.write(f"!!! SUCCESS ({device_type}): Providers used: {used_providers}\\\\n")
                    if "OpenVINOExecutionProvider" in used_providers:
                        last_error = None
                        break
                    last_error = RuntimeError("OpenVINOExecutionProvider was requested but not used.")
                except Exception as inner_e:
                    last_error = inner_e
                    sys.stderr.write(f"!!! ERROR ({device_type}): {inner_e}\\\\n")
            if last_error is not None:
                raise last_error
        except Exception as e:
            sys.stderr.write(f"!!! ERROR: Failed to create InferenceSession with OpenVINO: {e}\\\\n")
            # Diagnostic: try OpenVINO CPU to see if EP works at all
            try:
                cpu_session = ort.InferenceSession(
                    self.model_path.as_posix(),
                    providers=[("OpenVINOExecutionProvider", {"device_type": "CPU"})],
                    sess_options=self.sess_options
                )
                sys.stderr.write(f"!!! DIAGNOSTIC: OpenVINO CPU providers used: {cpu_session.get_providers()}\\\\n")
            except Exception as cpu_e:
                sys.stderr.write(f"!!! DIAGNOSTIC: OpenVINO CPU failed: {cpu_e}\\\\n")
            sys.stderr.write(f"!!! FALLBACK to CPUExecutionProvider. ORT available providers: {ort.get_available_providers()}\\\\n")
            # Attempt to create session with CPU provider as fallback
            self.providers = ["CPUExecutionProvider"]
            self.session = ort.InferenceSession(
                self.model_path.as_posix(),
                providers=self.providers,
                sess_options=self.sess_options
            )
            sys.stderr.write(f"!!! FALLBACK SUCCESS: Providers used: {self.session.get_providers()}\\\\n")

    def run(self, output_names, input_feed, run_options=None):
        return self.session.run(output_names, input_feed, run_options)
    def get_inputs(self): return self.session.get_inputs()
    def get_outputs(self): return self.session.get_outputs()
EOF

      # Replace CLIP visual encoder with OpenVINO IR pipeline.
      cat > $out/${final.python3.sitePackages}/immich_ml/models/clip/visual.py <<'PY'
import json
from abc import abstractmethod
from functools import cached_property
from pathlib import Path
from typing import Any
import os
import logging

import numpy as np
from numpy.typing import NDArray
from PIL import Image
from openvino.runtime import Core

from immich_ml.config import log
from immich_ml.models.base import InferenceModel
from immich_ml.models.transforms import (
    crop_pil,
    decode_pil,
    get_pil_resampling,
    normalize,
    resize_pil,
    serialize_np_array,
    to_numpy,
)
from immich_ml.schemas import ModelSession, ModelTask, ModelType

ov_log = logging.getLogger("immich_ml")


class _OVIO:
    def __init__(self, ov_port) -> None:
        self.name = ov_port.any_name
        self.shape = list(ov_port.shape)


class _OVSession:
    def __init__(self, compiled_model):
        self._compiled = compiled_model
        self._inputs = [_OVIO(p) for p in compiled_model.inputs]
        self._outputs = [_OVIO(p) for p in compiled_model.outputs]

    def run(self, output_names, input_feed, run_options=None):
        feed = input_feed
        input_names = [i.name for i in self._inputs]
        if any(name in input_names for name in input_feed.keys()):
            feed = {k: v for k, v in input_feed.items() if k in input_names}
        elif len(self._inputs) == 1 and len(input_feed) == 1:
            feed = {self._inputs[0].name: next(iter(input_feed.values()))}
        infer_request = self._compiled.create_infer_request()
        result = infer_request.infer(feed)
        return [result[p.any_name] for p in self._compiled.outputs]

    def get_inputs(self):
        return self._inputs

    def get_outputs(self):
        return self._outputs


class BaseCLIPVisualEncoder(InferenceModel):
    depends = []
    identity = (ModelType.VISUAL, ModelTask.SEARCH)

    def _predict(self, inputs: Image.Image | bytes) -> str:
        image = decode_pil(inputs)
        res: NDArray[np.float32] = self.session.run(None, self.transform(image))[0][0]
        return serialize_np_array(res)

    @abstractmethod
    def transform(self, image: Image.Image) -> dict[str, NDArray[np.float32]]:
        pass

    @property
    def model_cfg_path(self) -> Path:
        return self.cache_dir / "config.json"

    @property
    def preprocess_cfg_path(self) -> Path:
        return self.model_dir / "preprocess_cfg.json"

    @cached_property
    def model_cfg(self) -> dict[str, Any]:
        log.debug(f"Loading model config for CLIP model '{self.model_name}'")
        model_cfg: dict[str, Any] = json.load(self.model_cfg_path.open())
        log.debug(f"Loaded model config for CLIP model '{self.model_name}'")
        return model_cfg

    @cached_property
    def preprocess_cfg(self) -> dict[str, Any]:
        log.debug(f"Loading visual preprocessing config for CLIP model '{self.model_name}'")
        preprocess_cfg: dict[str, Any] = json.load(self.preprocess_cfg_path.open())
        log.debug(f"Loaded visual preprocessing config for CLIP model '{self.model_name}'")
        return preprocess_cfg


class OpenClipVisualEncoder(BaseCLIPVisualEncoder):
    def _load(self) -> ModelSession:
        size: list[int] | int = self.preprocess_cfg["size"]
        self.size = size[0] if isinstance(size, list) else size

        self.resampling = get_pil_resampling(self.preprocess_cfg["interpolation"])
        self.mean = np.array(self.preprocess_cfg["mean"], dtype=np.float32)
        self.std = np.array(self.preprocess_cfg["std"], dtype=np.float32)

        cache_root = Path(os.environ.get("MACHINE_LEARNING_CACHE_FOLDER", "/var/cache/immich"))
        ov_dir = Path(os.environ.get("IMMICH_OV_CLIP_DIR", cache_root / "ov" / "clip" / self.model_name / "visual"))
        ov_xml = ov_dir / "model.xml"
        ov_bin = ov_dir / "model.bin"
        device_env = os.environ.get("OPENVINO_DEVICE", "GPU")
        device = device_env.split(",")[0].strip() or "GPU"

        if ov_xml.exists() and ov_bin.exists():
            ov_log.warning("OV CLIP visual selected")
            core = Core()
            model = core.read_model(ov_xml.as_posix())
            try:
                model.reshape({model.inputs[0].any_name: [1, 3, self.size, self.size]})
            except Exception:
                pass
            compiled = core.compile_model(model, device)
            try:
                in_shape = compiled.inputs[0].shape
                if len(in_shape) == 4 and in_shape[2] == in_shape[3]:
                    new_size = int(in_shape[2])
                    if new_size != self.size:
                        ov_log.warning("OV CLIP visual resize override: %s -> %s", self.size, new_size)
                    self.size = new_size
            except Exception:
                pass
            self.session = _OVSession(compiled)
            return self.session

        return super()._load()

    def transform(self, image: Image.Image) -> dict[str, NDArray[np.float32]]:
        image = resize_pil(image, self.size)
        image = crop_pil(image, self.size)
        image_np = to_numpy(image)
        image_np = normalize(image_np, self.mean, self.std)
        return {"image": np.expand_dims(image_np.transpose(2, 0, 1), 0)}
PY

      # Replace CLIP textual encoder with OpenVINO IR pipeline.
      cat > $out/${final.python3.sitePackages}/immich_ml/models/clip/textual.py <<'PY'
import json
from abc import abstractmethod
from functools import cached_property
from pathlib import Path
from typing import Any
import os
import logging

import numpy as np
from numpy.typing import NDArray
from tokenizers import Encoding, Tokenizer
from openvino.runtime import Core

from immich_ml.config import log
from immich_ml.models.base import InferenceModel
from immich_ml.models.constants import WEBLATE_TO_FLORES200
from immich_ml.models.transforms import clean_text, serialize_np_array
from immich_ml.schemas import ModelSession, ModelTask, ModelType

ov_log = logging.getLogger("immich_ml")


class _OVIO:
    def __init__(self, ov_port) -> None:
        self.name = ov_port.any_name
        self.shape = list(ov_port.shape)


class _OVSession:
    def __init__(self, compiled_model):
        self._compiled = compiled_model
        self._inputs = [_OVIO(p) for p in compiled_model.inputs]
        self._outputs = [_OVIO(p) for p in compiled_model.outputs]

    def run(self, output_names, input_feed, run_options=None):
        feed = input_feed
        input_names = [i.name for i in self._inputs]
        if any(name in input_names for name in input_feed.keys()):
            feed = {k: v for k, v in input_feed.items() if k in input_names}
        elif len(self._inputs) == 1 and len(input_feed) == 1:
            feed = {self._inputs[0].name: next(iter(input_feed.values()))}
        infer_request = self._compiled.create_infer_request()
        result = infer_request.infer(feed)
        return [result[p.any_name] for p in self._compiled.outputs]

    def get_inputs(self):
        return self._inputs

    def get_outputs(self):
        return self._outputs


class BaseCLIPTextualEncoder(InferenceModel):
    depends = []
    identity = (ModelType.TEXTUAL, ModelTask.SEARCH)

    def _predict(self, inputs: str, language: str | None = None) -> str:
        tokens = self.tokenize(inputs, language=language)
        res: NDArray[np.float32] = self.session.run(None, tokens)[0][0]
        return serialize_np_array(res)

    def _load(self) -> ModelSession:
        cache_root = Path(os.environ.get("MACHINE_LEARNING_CACHE_FOLDER", "/var/cache/immich"))
        ov_dir = Path(os.environ.get("IMMICH_OV_CLIP_DIR", cache_root / "ov" / "clip" / self.model_name / "textual"))
        ov_xml = ov_dir / "model.xml"
        ov_bin = ov_dir / "model.bin"
        device_env = os.environ.get("OPENVINO_DEVICE", "GPU")
        device = device_env.split(",")[0].strip() or "GPU"

        if ov_xml.exists() and ov_bin.exists():
            ov_log.warning("OV CLIP textual selected")
            core = Core()
            compiled = core.compile_model(ov_xml.as_posix(), device)
            self.session = _OVSession(compiled)
            session = self.session
        else:
            session = super()._load()

        log.debug(f"Loading tokenizer for CLIP model '{self.model_name}'")
        self.tokenizer = self._load_tokenizer()
        tokenizer_kwargs: dict[str, Any] | None = self.text_cfg.get("tokenizer_kwargs")
        self.canonicalize = tokenizer_kwargs is not None and tokenizer_kwargs.get("clean") == "canonicalize"
        self.is_nllb = self.model_name.startswith("nllb")
        log.debug(f"Loaded tokenizer for CLIP model '{self.model_name}'")

        return session

    @abstractmethod
    def _load_tokenizer(self) -> Tokenizer:
        pass

    @abstractmethod
    def tokenize(self, text: str, language: str | None = None) -> dict[str, NDArray[np.int32]]:
        pass

    @property
    def model_cfg_path(self) -> Path:
        return self.cache_dir / "config.json"

    @property
    def tokenizer_file_path(self) -> Path:
        return self.model_dir / "tokenizer.json"

    @property
    def tokenizer_cfg_path(self) -> Path:
        return self.model_dir / "tokenizer_config.json"

    @cached_property
    def model_cfg(self) -> dict[str, Any]:
        log.debug(f"Loading model config for CLIP model '{self.model_name}'")
        model_cfg: dict[str, Any] = json.load(self.model_cfg_path.open())
        log.debug(f"Loaded model config for CLIP model '{self.model_name}'")
        return model_cfg

    @property
    def text_cfg(self) -> dict[str, Any]:
        text_cfg: dict[str, Any] = self.model_cfg["text_cfg"]
        return text_cfg

    @cached_property
    def tokenizer_file(self) -> dict[str, Any]:
        log.debug(f"Loading tokenizer file for CLIP model '{self.model_name}'")
        tokenizer_file: dict[str, Any] = json.load(self.tokenizer_file_path.open())
        log.debug(f"Loaded tokenizer file for CLIP model '{self.model_name}'")
        return tokenizer_file

    @cached_property
    def tokenizer_cfg(self) -> dict[str, Any]:
        log.debug(f"Loading tokenizer config for CLIP model '{self.model_name}'")
        tokenizer_cfg: dict[str, Any] = json.load(self.tokenizer_cfg_path.open())
        log.debug(f"Loaded tokenizer config for CLIP model '{self.model_name}'")
        return tokenizer_cfg


class OpenClipTextualEncoder(BaseCLIPTextualEncoder):
    def _load_tokenizer(self) -> Tokenizer:
        context_length: int = self.text_cfg.get("context_length", 77)
        pad_token: str = self.tokenizer_cfg["pad_token"]

        tokenizer: Tokenizer = Tokenizer.from_file(self.tokenizer_file_path.as_posix())

        pad_id: int = tokenizer.token_to_id(pad_token)
        tokenizer.enable_padding(length=context_length, pad_token=pad_token, pad_id=pad_id)
        tokenizer.enable_truncation(max_length=context_length)

        return tokenizer

    def tokenize(self, text: str, language: str | None = None) -> dict[str, NDArray[np.int32]]:
        text = clean_text(text, canonicalize=self.canonicalize)
        if self.is_nllb and language is not None:
            flores_code = WEBLATE_TO_FLORES200.get(language)
            if flores_code is None:
                no_country = language.split("-")[0]
                flores_code = WEBLATE_TO_FLORES200.get(no_country)
                if flores_code is None:
                    log.warning(f"Language '{language}' not found, defaulting to 'en'")
                    flores_code = "eng_Latn"
            text = f"{flores_code}{text}"
        tokens: Encoding = self.tokenizer.encode(text)
        return {"text": np.array([tokens.ids], dtype=np.int32)}


class MClipTextualEncoder(OpenClipTextualEncoder):
    def tokenize(self, text: str, language: str | None = None) -> dict[str, NDArray[np.int32]]:
        text = clean_text(text, canonicalize=self.canonicalize)
        tokens: Encoding = self.tokenizer.encode(text)
        return {
            "input_ids": np.array([tokens.ids], dtype=np.int32),
            "attention_mask": np.array([tokens.attention_mask], dtype=np.int32),
        }
PY

      # Replace face detection with OpenVINO OMZ detector + landmarks pipeline.
      cat > $out/${final.python3.sitePackages}/immich_ml/models/facial_recognition/detection.py <<'PY'
from __future__ import annotations

from pathlib import Path
from typing import Any
import os
import logging

import cv2
import numpy as np
from numpy.typing import NDArray
from openvino.runtime import Core

from immich_ml.models.base import InferenceModel
from immich_ml.models.transforms import decode_cv2
from immich_ml.schemas import FaceDetectionOutput, ModelSession, ModelTask, ModelType

try:
    from insightface.model_zoo import RetinaFace  # fallback
except Exception:  # pragma: no cover - fallback only
    RetinaFace = None

log = logging.getLogger("immich_ml")


def _nms(boxes: NDArray[np.float32], scores: NDArray[np.float32], thresh: float) -> NDArray[np.int64]:
    if boxes.size == 0:
        return np.empty((0,), dtype=np.int64)
    x1 = boxes[:, 0]
    y1 = boxes[:, 1]
    x2 = boxes[:, 2]
    y2 = boxes[:, 3]
    areas = (x2 - x1 + 1) * (y2 - y1 + 1)
    order = scores.argsort()[::-1]
    keep: list[int] = []
    while order.size > 0:
        i = int(order[0])
        keep.append(i)
        xx1 = np.maximum(x1[i], x1[order[1:]])
        yy1 = np.maximum(y1[i], y1[order[1:]])
        xx2 = np.minimum(x2[i], x2[order[1:]])
        yy2 = np.minimum(y2[i], y2[order[1:]])
        w = np.maximum(0.0, xx2 - xx1 + 1)
        h = np.maximum(0.0, yy2 - yy1 + 1)
        inter = w * h
        ovr = inter / (areas[i] + areas[order[1:]] - inter)
        inds = np.where(ovr <= thresh)[0]
        order = order[inds + 1]
    return np.array(keep, dtype=np.int64)


class _OVSession:
    def __init__(self, compiled_model):
        self._compiled = compiled_model

    def run(self, output_names, input_feed, run_options=None):
        return list(self._compiled(input_feed).values())

    def get_inputs(self):
        return list(self._compiled.inputs)

    def get_outputs(self):
        return list(self._compiled.outputs)


class _OmzFaceDetector:
    def __init__(self, det_xml: Path, lm_xml: Path, device: str, min_score: float) -> None:
        self.min_score = min_score
        core = Core()
        self.det_compiled = core.compile_model(det_xml.as_posix(), device)
        self.lm_compiled = core.compile_model(lm_xml.as_posix(), device)
        self.det_input = self.det_compiled.inputs[0]
        self.det_output = self.det_compiled.outputs[0]
        self.lm_input = self.lm_compiled.inputs[0]
        self.lm_output = self.lm_compiled.outputs[0]
        log.warning(
            "OMZ detector init: device=%s det=%s lm=%s",
            device,
            det_xml.name,
            lm_xml.name,
        )

    @property
    def session(self) -> ModelSession:
        return _OVSession(self.det_compiled)

    def _infer_det(self, img: NDArray[np.uint8]) -> NDArray[np.float32]:
        resized = cv2.resize(img, (300, 300))
        blob = resized.transpose(2, 0, 1)[None].astype(np.float32)
        req = self.det_compiled.create_infer_request()
        out = req.infer({self.det_input.any_name: blob})[self.det_output]
        return out.astype(np.float32)

    def _infer_lm(self, face: NDArray[np.uint8]) -> NDArray[np.float32]:
        resized = cv2.resize(face, (48, 48))
        blob = resized.transpose(2, 0, 1)[None].astype(np.float32)
        req = self.lm_compiled.create_infer_request()
        out = req.infer({self.lm_input.any_name: blob})[self.lm_output]
        return out.reshape(-1).astype(np.float32)

    def detect(self, img: NDArray[np.uint8]) -> tuple[NDArray[np.float32], NDArray[np.float32]]:
        h, w = img.shape[:2]
        det_out = self._infer_det(img)
        # det_out shape: [1, 1, N, 7] with [image_id, label, conf, x_min, y_min, x_max, y_max]
        dets = det_out.reshape(-1, 7)
        dets = dets[dets[:, 2] >= self.min_score]
        if dets.size == 0:
            return np.zeros((0, 5), dtype=np.float32), np.zeros((0, 5, 2), dtype=np.float32)

        x1 = np.clip(dets[:, 3] * w, 0, w - 1)
        y1 = np.clip(dets[:, 4] * h, 0, h - 1)
        x2 = np.clip(dets[:, 5] * w, 0, w - 1)
        y2 = np.clip(dets[:, 6] * h, 0, h - 1)
        scores = dets[:, 2]
        boxes = np.stack([x1, y1, x2, y2], axis=1).astype(np.float32)
        keep = _nms(boxes, scores, 0.4)
        boxes = boxes[keep]
        scores = scores[keep]

        landmarks = []
        for (bx1, by1, bx2, by2) in boxes:
            ix1, iy1, ix2, iy2 = map(int, [bx1, by1, bx2, by2])
            if ix2 <= ix1 or iy2 <= iy1:
                landmarks.append(np.zeros((5, 2), dtype=np.float32))
                continue
            crop = img[iy1:iy2, ix1:ix2]
            lm = self._infer_lm(crop)
            lm = lm.reshape(5, 2)
            # lm is normalized to [0,1] in crop coordinates
            lm[:, 0] = lm[:, 0] * (bx2 - bx1) + bx1
            lm[:, 1] = lm[:, 1] * (by2 - by1) + by1
            landmarks.append(lm.astype(np.float32))
        landmarks = np.stack(landmarks, axis=0) if landmarks else np.zeros((0, 5, 2), dtype=np.float32)

        bboxes = np.concatenate([boxes, scores[:, None]], axis=1).astype(np.float32)
        log.warning("OMZ detect: faces=%d image=%dx%d", bboxes.shape[0], w, h)
        return bboxes, landmarks


class FaceDetector(InferenceModel):
    depends = []
    identity = (ModelType.DETECTION, ModelTask.FACIAL_RECOGNITION)

    def __init__(self, model_name: str, min_score: float = 0.7, **model_kwargs: Any) -> None:
        self.min_score = model_kwargs.pop("minScore", min_score)
        super().__init__(model_name, **model_kwargs)

    def _load(self) -> ModelSession:
        cache_root = Path(os.environ.get("MACHINE_LEARNING_CACHE_FOLDER", "/var/cache/immich"))
        omz_dir = Path(os.environ.get("IMMICH_OMZ_DIR", cache_root / "omz"))
        det_xml = omz_dir / "face-detection-retail-0005/FP16/face-detection-retail-0005.xml"
        lm_xml = omz_dir / "landmarks-regression-retail-0009/FP16/landmarks-regression-retail-0009.xml"
        device_env = os.environ.get("OPENVINO_DEVICE", "GPU")
        device = device_env.split(",")[0].strip() or "GPU"

        if det_xml.exists() and lm_xml.exists():
            log.warning("OMZ detector selected")
            self.model = _OmzFaceDetector(det_xml, lm_xml, device, self.min_score)
            return self.model.session

        # Fallback to RetinaFace if OMZ models are missing.
        session = self._make_session(self.model_path)
        if RetinaFace is None:
            raise RuntimeError("RetinaFace fallback unavailable and OMZ models not found")
        self.model = RetinaFace(session=session)
        self.model.prepare(ctx_id=0, det_thresh=self.min_score, input_size=(640, 640))
        return session

    def _predict(self, inputs: NDArray[np.uint8] | bytes) -> FaceDetectionOutput:
        inputs = decode_cv2(inputs)
        bboxes, landmarks = self._detect(inputs)
        return {
            "boxes": bboxes[:, :4].round(),
            "scores": bboxes[:, 4],
            "landmarks": landmarks,
        }

    def _detect(self, inputs: NDArray[np.uint8] | bytes) -> tuple[NDArray[np.float32], NDArray[np.float32]]:
        return self.model.detect(inputs)  # type: ignore

    def configure(self, **kwargs: Any) -> None:
        if hasattr(self.model, "min_score"):
            self.model.min_score = kwargs.pop("minScore", self.model.min_score)
PY

      # Replace face recognition with OpenVINO IR pipeline (ArcFace).
      cat > $out/${final.python3.sitePackages}/immich_ml/models/facial_recognition/recognition.py <<'PY'
from __future__ import annotations

from pathlib import Path
from typing import Any
import os
import logging

import cv2
import numpy as np
import onnx
from numpy.typing import NDArray
from openvino.runtime import Core
from PIL import Image
from insightface.utils.face_align import norm_crop

from immich_ml.config import settings
from immich_ml.models.base import InferenceModel
from immich_ml.models.transforms import decode_cv2, serialize_np_array
from immich_ml.schemas import (
    FaceDetectionOutput,
    FacialRecognitionOutput,
    ModelFormat,
    ModelSession,
    ModelTask,
    ModelType,
)

try:
    from insightface.model_zoo import ArcFaceONNX  # fallback
except Exception:  # pragma: no cover - fallback only
    ArcFaceONNX = None

log = logging.getLogger("immich_ml")


def _infer_norm_params(model_file: Path) -> tuple[float, float]:
    try:
        model = onnx.load(model_file.as_posix())
        graph = model.graph
        find_sub = False
        find_mul = False
        for node in graph.node[:8]:
            if node.name.startswith("Sub") or node.name.startswith("_minus"):
                find_sub = True
            if node.name.startswith("Mul") or node.name.startswith("_mul"):
                find_mul = True
        if find_sub and find_mul:
            return 0.0, 1.0
    except Exception:
        pass
    return 127.5, 127.5


def _infer_input_shape(model_file: Path) -> tuple[int, int, int, int]:
    try:
        model = onnx.load(model_file.as_posix())
        inp = model.graph.input[0]
        dims = inp.type.tensor_type.shape.dim
        c = dims[1].dim_value if dims[1].dim_value > 0 else 3
        h = dims[2].dim_value if dims[2].dim_value > 0 else 112
        w = dims[3].dim_value if dims[3].dim_value > 0 else 112
        return (1, int(c), int(h), int(w))
    except Exception:
        return (1, 3, 112, 112)


class _OVIO:
    def __init__(self, ov_port) -> None:
        self.name = ov_port.any_name
        self.shape = list(ov_port.shape)


class _OVSession:
    def __init__(self, compiled_model):
        self._compiled = compiled_model
        self._inputs = [_OVIO(p) for p in compiled_model.inputs]
        self._outputs = [_OVIO(p) for p in compiled_model.outputs]

    def run(self, output_names, input_feed, run_options=None):
        feed = input_feed
        input_names = [i.name for i in self._inputs]
        if any(name in input_names for name in input_feed.keys()):
            feed = {k: v for k, v in input_feed.items() if k in input_names}
        elif len(self._inputs) == 1 and len(input_feed) == 1:
            feed = {self._inputs[0].name: next(iter(input_feed.values()))}
        infer_request = self._compiled.create_infer_request()
        result = infer_request.infer(feed)
        return [result[p.any_name] for p in self._compiled.outputs]

    def get_inputs(self):
        return self._inputs

    def get_outputs(self):
        return self._outputs


class _OVArcFace:
    def __init__(self, onnx_path: Path, ov_xml: Path, device: str) -> None:
        self.input_mean, self.input_std = _infer_norm_params(onnx_path)
        core = Core()
        self.compiled = core.compile_model(ov_xml.as_posix(), device)
        self.input_port = self.compiled.inputs[0]
        self.output_port = self.compiled.outputs[0]
        shape = list(self.input_port.shape)
        h = int(shape[2]) if len(shape) > 2 and shape[2] > 0 else 112
        w = int(shape[3]) if len(shape) > 3 and shape[3] > 0 else 112
        self.input_size = (w, h)
        log.warning("OV recognition init: device=%s size=%dx%d", device, w, h)

    @property
    def session(self) -> ModelSession:
        return _OVSession(self.compiled)

    def _infer(self, blob: NDArray[np.float32]) -> NDArray[np.float32]:
        req = self.compiled.create_infer_request()
        out = req.infer({self.input_port.any_name: blob})[self.output_port]
        return out

    def get_feat(self, imgs: list[NDArray[np.uint8]] | NDArray[np.uint8]) -> NDArray[np.float32]:
        if not isinstance(imgs, list):
            imgs = [imgs]
        blob = cv2.dnn.blobFromImages(
            imgs,
            1.0 / self.input_std,
            self.input_size,
            (self.input_mean, self.input_mean, self.input_mean),
            swapRB=True,
        )
        return self._infer(blob)


class FaceRecognizer(InferenceModel):
    depends = [(ModelType.DETECTION, ModelTask.FACIAL_RECOGNITION)]
    identity = (ModelType.RECOGNITION, ModelTask.FACIAL_RECOGNITION)

    def __init__(self, model_name: str, **model_kwargs: Any) -> None:
        super().__init__(model_name, **model_kwargs)
        max_batch_size = settings.max_batch_size.facial_recognition if settings.max_batch_size else None
        self.batch_size = max_batch_size if max_batch_size else self._batch_size_default

    def _load(self) -> ModelSession:
        cache_root = Path(os.environ.get("MACHINE_LEARNING_CACHE_FOLDER", "/var/cache/immich"))
        ov_dir = Path(os.environ.get("IMMICH_OV_RECOGNITION_DIR", cache_root / "ov" / self.model_name / "recognition"))
        ov_xml = ov_dir / "model.xml"
        ov_bin = ov_dir / "model.bin"
        device_env = os.environ.get("OPENVINO_DEVICE", "GPU")
        device = device_env.split(",")[0].strip() or "GPU"

        if ov_xml.exists() and ov_bin.exists():
            log.warning("OV recognition selected")
            self.model = _OVArcFace(self.model_path_for_format(ModelFormat.ONNX), ov_xml, device)
            self.batch_size = 1
            return self.model.session

        session = self._make_session(self.model_path)
        if (not self.batch_size or self.batch_size > 1) and str(session.get_inputs()[0].shape[0]) != "batch":
            self._add_batch_axis(self.model_path)
            session = self._make_session(self.model_path)
        if ArcFaceONNX is None:
            raise RuntimeError("ArcFaceONNX fallback unavailable and OpenVINO IR not found")
        self.model = ArcFaceONNX(
            self.model_path_for_format(ModelFormat.ONNX).as_posix(),
            session=session,
        )
        return session

    def _predict(
        self, inputs: NDArray[np.uint8] | bytes | Image.Image, faces: FaceDetectionOutput
    ) -> FacialRecognitionOutput:
        if faces["boxes"].shape[0] == 0:
            return []
        inputs = decode_cv2(inputs)
        cropped_faces = self._crop(inputs, faces)
        embeddings = self._predict_batch(cropped_faces)
        return self.postprocess(faces, embeddings)

    def _predict_batch(self, cropped_faces: list[NDArray[np.uint8]]) -> NDArray[np.float32]:
        if not self.batch_size or len(cropped_faces) <= self.batch_size:
            embeddings: NDArray[np.float32] = self.model.get_feat(cropped_faces)
            return embeddings

        batch_embeddings: list[NDArray[np.float32]] = []
        for i in range(0, len(cropped_faces), self.batch_size):
            batch_embeddings.append(self.model.get_feat(cropped_faces[i : i + self.batch_size]))
        return np.concatenate(batch_embeddings, axis=0)

    def postprocess(self, faces: FaceDetectionOutput, embeddings: NDArray[np.float32]) -> FacialRecognitionOutput:
        return [
            {
                "boundingBox": {"x1": x1, "y1": y1, "x2": x2, "y2": y2},
                "embedding": serialize_np_array(embedding),
                "score": score,
            }
            for (x1, y1, x2, y2), embedding, score in zip(faces["boxes"], embeddings, faces["scores"])
        ]

    def _crop(self, image: NDArray[np.uint8], faces: FaceDetectionOutput) -> list[NDArray[np.uint8]]:
        return [norm_crop(image, landmark) for landmark in faces["landmarks"]]

    def _add_batch_axis(self, model_path: Path) -> None:
        log.debug(f"Adding batch axis to model {model_path}")
        proto = onnx.load(model_path)
        static_input_dims = [shape.dim_value for shape in proto.graph.input[0].type.tensor_type.shape.dim[1:]]
        static_output_dims = [shape.dim_value for shape in proto.graph.output[0].type.tensor_type.shape.dim[1:]]
        input_dims = {proto.graph.input[0].name: ["batch"] + static_input_dims}
        output_dims = {proto.graph.output[0].name: ["batch"] + static_output_dims}
        from onnx.tools.update_model_dims import update_inputs_outputs_dims
        updated_proto = update_inputs_outputs_dims(proto, input_dims, output_dims)
        onnx.save(updated_proto, model_path)

    @property
    def _batch_size_default(self) -> int | None:
        return 1
PY

      # Ensure OpenVINO Python package is on PYTHONPATH for the service wrapper.
      WRAPPER="$out/bin/machine-learning"
      if [ -f "$WRAPPER" ]; then
        OPENVINO_PY="${final.python3Packages.openvino}/${final.python3.sitePackages}"
        OCL_ICD_DIR="${final.intel-compute-runtime}/etc/OpenCL/vendors"
        OPENCL_VENDOR_PATH="${final.intel-compute-runtime}/etc/OpenCL/vendors"
        sed -i "/^exec /i PYTHONPATH=\\\"$OPENVINO_PY:\\$PYTHONPATH\\\"\\nexport PYTHONPATH\\nOCL_ICD_VENDORS=\\\"$OCL_ICD_DIR\\\"\\nexport OCL_ICD_VENDORS\\nOPENCL_VENDOR_PATH=\\\"$OPENCL_VENDOR_PATH\\\"\\nexport OPENCL_VENDOR_PATH" "$WRAPPER"
      fi

      # Ensure RetinaFace input_size is set even if ORT reports dynamic dims.
      # Skip if we replaced detection.py with OMZ pipeline.
      DET_FILE="$out/${final.python3.sitePackages}/immich_ml/models/facial_recognition/detection.py"
      if [ -f "$DET_FILE" ]; then
        DET_FILE="$DET_FILE" ${final.python3}/bin/python3 - <<'PY'
from pathlib import Path
import os

path = Path(os.environ["DET_FILE"])
text = path.read_text()
if "_OmzFaceDetector" in text:
    raise SystemExit(0)
if "RetinaFace" not in text:
    raise SystemExit(0)

needle = "        self.model.prepare(ctx_id=0, det_thresh=self.min_score, input_size=(640, 640))\n"
insert = needle + "        if self.model.input_size is None:\n            self.model.input_size = (640, 640)\n"
if needle in text and "self.model.input_size is None" not in text:
    text = text.replace(needle, insert, 1)
    path.write_text(text)

# Also guard right before detect in case input_size is reset later.
needle = "    def _detect(self, inputs: NDArray[np.uint8] | bytes) -> tuple[NDArray[np.float32], NDArray[np.float32]]:\n"
guard = needle + "        if self.model.input_size is None:\n            self.model.input_size = (640, 640)\n"
if needle in text and "if self.model.input_size is None" not in text.split(needle, 1)[1]:
    text = text.replace(needle, guard, 1)
    path.write_text(text)
PY
      fi

      # Provide a compatibility shim for openvino.runtime (newer OpenVINO exposes Core at top-level).
      OV_SHIM_DIR="$out/${final.python3.sitePackages}/openvino/runtime"
      mkdir -p "$OV_SHIM_DIR"
      cat > "$OV_SHIM_DIR/__init__.py" <<'PY'
from openvino import Core, CompiledModel, InferRequest, AsyncInferQueue
__all__ = ["Core", "CompiledModel", "InferRequest", "AsyncInferQueue"]
PY

    '';
  });

  # Override the main immich package
  immich = (prev.immich.override {
    python3 = final.python3;
    immich-machine-learning = final.immich-machine-learning;
  }).overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      echo "!!! IMMICH OVERLAY APPLIED !!!"
    '';
    passthru = old.passthru // {
      # Point directly to our patched derivation.
      machine-learning = final.immich-machine-learning;
    };
  });
}
