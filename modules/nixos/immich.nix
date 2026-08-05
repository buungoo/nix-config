{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  cfg = config.custom.services.immich;
  net = lib.custom.mkContainerNetworkConfig config cfg.network "immich";
  hostConfig = config;

  immichMedia = "/var/lib/immich";
  uid = toString cfg.uid;
  gid = toString cfg.gid;

  sopsFolder = builtins.toString inputs.nix-secrets + "/sops";
  siglip256Root = inputs.siglip256;
in
{
  options.custom.services.immich = {
    enable = lib.mkEnableOption "Immich photo management solution";

    uid = lib.mkOption {
      type = lib.types.int;
      default = 10900;
      description = "UID for immich user on both host and container";
    };

    gid = lib.mkOption {
      type = lib.types.int;
      default = 10900;
      description = "GID for immich group on both host and container";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "immich.${config.hostSpec.domain}";
      description = "FQDN for the Immich reverse proxy virtual host";
    };

    network = lib.mkOption {
      type = lib.types.str;
      default = "immich";
      description = "Which containerNetwork to place immich on";
    };

    hostOctet = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = "Host octet for the container IP";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 2283;
      description = "Immich HTTP port";
    };

    applicationDataPath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/immich";
      description = "Host path for application data (database, etc.)";
    };

    mediaLocation = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/storage/immich";
      description = "Host path for Immich media storage (library, thumbs, etc.)";
    };

    gpu = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable GPU hardware acceleration";
      };
      renderDevice = lib.mkOption {
        type = lib.types.str;
        default = hostConfig.hostSpec.gpu.renderDevice;
        description = "Path to GPU render device";
      };
      cardDevice = lib.mkOption {
        type = lib.types.str;
        default = hostConfig.hostSpec.gpu.cardDevice;
        description = "Path to GPU card device";
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.custom.mkContainerServiceConfig "immich" { })
      {
        # Create user on host
        users.users.immich = {
          isSystemUser = true;
          group = "immich";
          extraGroups = lib.optionals cfg.gpu.enable [
            "video"
            "render"
          ];
          uid = cfg.uid;
        };
        users.groups.immich.gid = cfg.gid;

        # Register reverse proxy
        custom.reverseProxy.virtualHosts.immich = {
          domain = cfg.domain;
          backendHost = net.containerIP;
          backendPort = cfg.port;
          backendSSL = false;
        };

        # Register container network
        hostSpec.networking.containerNetworks.${cfg.network} = {
          bridge = lib.mkDefault "${cfg.network}-bridge";
          subnet = lib.mkDefault "10.0.0.0/24";
          gateway = lib.mkDefault "10.0.0.1";
          containers.immich = lib.mkDefault cfg.hostOctet;
        };

        # Sops secrets
        sops.secrets."immich/oidc-client-secret" = {
          sopsFile = "${sopsFolder}/shared.yaml";
          owner = "root";
          group = "kanidm";
          mode = "0440";
        };

        # Kanidm OAuth client
        custom.kanidm.oauthClients.immich = {
          displayName = "Immich";
          originUrl = [
            "https://${cfg.domain}/auth/login"
            "https://${cfg.domain}/api/oauth/mobile-redirect"
            "https://${cfg.domain}/user-settings"
            "app.immich:///oauth-callback"
            "app.immich://oauth-callback"
            "app.immich:/oauth-callback"
            "com.alextran.immich://oauth-callback"
          ];
          originLanding = "https://${cfg.domain}/";
          secretFile = config.sops.secrets."immich/oidc-client-secret".path;
          enableLegacyCrypto = true;
          scopeMap.immich_users = [
            "openid"
            "email"
            "profile"
          ];
        };

        # Setup bindmount directories
        systemd.tmpfiles.rules = [
          "d ${cfg.applicationDataPath} 0755 ${uid} ${gid} -"
          "d ${cfg.mediaLocation} 0755 ${uid} ${gid} -"
          "d ${cfg.mediaLocation}/encoded-video 0755 ${uid} ${gid} -"
          "d ${cfg.mediaLocation}/thumbs 0755 ${uid} ${gid} -"
          "d ${cfg.mediaLocation}/upload 0755 ${uid} ${gid} -"
          "d ${cfg.mediaLocation}/library 0755 ${uid} ${gid} -"
          "d ${cfg.mediaLocation}/profile 0755 ${uid} ${gid} -"
          "d ${cfg.mediaLocation}/backups 0755 ${uid} ${gid} -"
          "d /var/cache/immich 0755 ${uid} ${gid} -"

          # Recursively fix ownership for the new UID/GID during migration
          "Z ${cfg.applicationDataPath} 0755 ${uid} ${gid} -"
          "Z ${cfg.mediaLocation} 0755 ${uid} ${gid} -"
          "Z /var/cache/immich 0755 ${uid} ${gid} -"
        ];
        # Alternative structured settings for comparison:
        # systemd.tmpfiles.settings."10-immich" = {
        #   "${cfg.applicationDataPath}" = {
        #     d = { mode = "0700"; user = uid; group = gid; };
        #     Z = { mode = "0700"; user = uid; group = gid; };
        #   };
        #   "${cfg.mediaLocation}" = {
        #     d = { mode = "0700"; user = uid; group = gid; };
        #     Z = { mode = "0700"; user = uid; group = gid; };
        #   };
        #   "${cfg.mediaLocation}/encoded-video".d = { mode = "0700"; user = uid; group = gid; };
        #   "${cfg.mediaLocation}/thumbs".d = { mode = "0700"; user = uid; group = gid; };
        #   "${cfg.mediaLocation}/upload".d = { mode = "0700"; user = uid; group = gid; };
        #   "${cfg.mediaLocation}/library".d = { mode = "0700"; user = uid; group = gid; };
        #   "${cfg.mediaLocation}/profile".d = { mode = "0700"; user = uid; group = gid; };
        #   "${cfg.mediaLocation}/backups".d = { mode = "0700"; user = uid; group = gid; };
        # };

        # Container definition
        containers.immich = {
          autoStart = true;
          ephemeral = true;

          bindMounts = lib.mkMerge [
            {
              "${immichMedia}" = {
                hostPath = cfg.mediaLocation;
                isReadOnly = false;
              };
              "/var/lib/postgresql" = {
                hostPath = cfg.applicationDataPath;
                isReadOnly = false;
              };
              "/var/cache/immich" = {
                hostPath = "/var/cache/immich";
                isReadOnly = false;
              };
              "/dev/bus/usb" = {
                hostPath = "/dev/bus/usb";
                isReadOnly = true;
              };
              "/run/secrets" = {
                hostPath = "/run/secrets";
                isReadOnly = true;
              };
            }
            (lib.mkIf cfg.gpu.enable {
              "/dev/dri" = {
                hostPath = "/dev/dri";
                isReadOnly = false;
              };
            })
          ];

          allowedDevices = lib.mkIf cfg.gpu.enable [
            {
              node = cfg.gpu.renderDevice;
              modifier = "rwm";
            }
            {
              node = cfg.gpu.cardDevice;
              modifier = "rwm";
            }
          ];

          privateNetwork = true;
          hostBridge = net.bridge;
          localAddress = "${net.containerIP}/${net.cidr}";

          forwardPorts = [
            {
              hostPort = cfg.port;
              containerPort = cfg.port;
            }
          ];

          config = lib.mkMerge [
            (lib.custom.mkContainerBaseConfig (net // { inherit (config.hostSpec) stateVersion; }))
            {
              environment.systemPackages = [
                pkgs.clinfo
                pkgs.intel-gpu-tools
              ];
              environment.sessionVariables = lib.mkIf cfg.gpu.enable {
                LIBVA_DRIVER_NAME = "iHD";
              };

              hardware.graphics = lib.mkIf cfg.gpu.enable {
                enable = true;
                extraPackages = hostConfig.hardware.graphics.extraPackages ++ [
                  pkgs.intel-compute-runtime
                  pkgs.intel-media-driver
                  pkgs.intel-ocl
                  pkgs.level-zero
                  pkgs.intel-vaapi-driver # i965 driver as requested/suggested
                ];
              };

              services.immich = {
                enable = true;
                package = pkgs.immich;
                database.enable = true;
                host = net.containerIP;
                openFirewall = true;
                mediaLocation = immichMedia;
                accelerationDevices = lib.optionals cfg.gpu.enable [
                  cfg.gpu.renderDevice
                  cfg.gpu.cardDevice
                ];
                environment = {
                  TZ = "Europe/Stockholm";
                  # Fix matplotlib and other python tools
                  MPLCONFIGDIR = "/tmp/matplotlib";
                };
                machine-learning.enable = true;
                machine-learning.environment = {
                  MACHINE_LEARNING_WORKERS = "1";
                  MACHINE_LEARNING_MAX_BATCH_SIZE__FACIAL_RECOGNITION = "1";
                  MACHINE_LEARNING_MAX_BATCH_SIZE__CLIP = "1";
                  MACHINE_LEARNING_MAX_BATCH_SIZE__OCR = "1";
                  MACHINE_LEARNING_OPENVINO_PRECISION = "FP16";
                  MACHINE_LEARNING_WORKER_TIMEOUT = lib.mkForce "300";
                  MACHINE_LEARNING_CACHE_FOLDER = "/var/cache/immich";
                  # Force GPU mode for Intel iGPUs
                  OPENVINO_DEVICE = "GPU,GPU_FP16,GPU.0";
                  MACHINE_LEARNING_DEVICE_IDS = "0";
                  OPENVINO_PERFORMANCE_HINT = "LATENCY";
                  # Fix for "dynamic shape without upper bound" on Intel iGPUs
                  ONNXRUNTIME_OPENVINO_ENABLE_DYNAMIC_SHAPES = "0";
                  OV_GPU_CACHE_DIR = "/var/cache/immich";
                  OV_GPU_ENABLE_PROPERTIES = "CACHE_DIR=/var/cache/immich";
                  # Enable debug logs
                  IMMICH_LOG_LEVEL = "debug";
                  # Enable verbose logs from ONNX Runtime and OpenVINO
                  ORT_LOG_LEVEL = "VERBOSE";
                  # Enable debug logs from OpenVINO itself
                  OV_LOG_LEVEL = "DEBUG";
                };
                settings = {
                  backup.database.enabled = false;
                  ffmpeg = {
                    accel = "qsv";
                    accelDecode = true;
                  };
                  machineLearning = {
                    clip = {
                      modelName = "ViT-L-16-SigLIP-256__webli";
                    };
                    facialRecognition = {
                      modelName = "buffalo_l";
                    };
                  };
                  oauth = {
                    enabled = true;
                    autoLaunch = true;
                    autoRegister = true;
                    buttonText = "Login";
                    clientId = "immich";
                    clientSecret._secret = hostConfig.sops.secrets."immich/oidc-client-secret".path;
                    issuerUrl = "https://${hostConfig.custom.reverseProxy.virtualHosts.auth.domain}/oauth2/openid/immich";
                    scope = "openid profile email";
                    signingAlgorithm = "RS256";
                    mobileRedirectUri = "app.immich:///oauth-callback";
                  };
                  passwordLogin.enabled = false;
                  server.externalDomain = "https://${cfg.domain}";
                };
              };

              # Patch InsightFace RetinaFace ONNX to static shape for OpenVINO GPU.
              systemd.services.immich-machine-learning.serviceConfig.TimeoutStartSec = "10min";
              systemd.services.immich-machine-learning.preStart = lib.mkBefore ''
                set -eu
                set -x

                LOG="/var/cache/immich/prestart.log"
                echo "=== preStart $(date -Is) ===" >> "$LOG"
                exec >> "$LOG" 2>&1
                echo "preStart begin"
                SED="${pkgs.gnused}/bin/sed"
                GREP="${pkgs.gnugrep}/bin/grep"
                AWK="${pkgs.gawk}/bin/awk"
                HEAD="${pkgs.coreutils}/bin/head"

                MODEL_DIR="/var/cache/immich/facial-recognition/buffalo_l/detection"
                MODEL="$MODEL_DIR/model.onnx"
                STATIC="$MODEL_DIR/model.static.onnx"
                ORIGINAL="$MODEL_DIR/model.dynamic.onnx"

                ml="$(systemctl show -p ExecStart --value immich-machine-learning | "$SED" -n "s/.*path=\\([^ ;]*\\).*/\\1/p")"
                gunicorn="$("$GREP" -oE "/nix/store/[^\"[:space:]]+-gunicorn-[^\"[:space:]]+/bin/gunicorn" "$ml" | "$HEAD" -n1)"
                wrapped="$("$GREP" -oE "/nix/store/[^\"[:space:]]+/bin/\\.gunicorn-wrapped" "$gunicorn" | "$HEAD" -n1)"
                python_path="$("$SED" -n "1{s/^#![[:space:]]*//;s/[[:space:]].*$//;p}" "$wrapped")"

                tmp_env="$(mktemp)"
                {
                  "$AWK" "/^PATH=|^export PATH|^export PYTHONNOUSERSITE/ {print}" "$gunicorn"
                  "$AWK" "/^PYTHONPATH=|^export PYTHONPATH/ {print}" "$ml"
                } > "$tmp_env"

                # Download OMZ face detection + landmarks models (IR) for OpenVINO.
                tmp_py_dl="$(mktemp)"
                cat > "$tmp_py_dl" <<'PY'
import os
import urllib.request
from pathlib import Path

base_url = "https://storage.openvinotoolkit.org/repositories/open_model_zoo/2023.0/models_bin/1"
base_dir = Path("/var/cache/immich/omz")
models = [
    "face-detection-retail-0005",
    "landmarks-regression-retail-0009",
]

def download(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists():
        return
    tmp = dest.with_suffix(dest.suffix + ".tmp")
    with urllib.request.urlopen(url) as r, open(tmp, "wb") as f:
        f.write(r.read())
    tmp.replace(dest)

for name in models:
    for ext in ("xml", "bin"):
        url = f"{base_url}/{name}/FP16/{name}.{ext}"
        dest = base_dir / name / "FP16" / f"{name}.{ext}"
        download(url, dest)
PY

                env -i PYTHON_PATH="$python_path" ENV_FILE="$tmp_env" sh -c '
                  set -eu
                  . "$ENV_FILE"
                  "$PYTHON_PATH" "$0"
                ' "$tmp_py_dl" >> "$LOG" 2>&1

                rm -f "$tmp_py_dl"

                # Seed SigLIP 256 model files from flake input to avoid runtime HF downloads.
                SIGLIP_ROOT="/var/cache/immich/clip/ViT-L-16-SigLIP-256__webli"
                SIGLIP_VIS="$SIGLIP_ROOT/visual"
                SIGLIP_TXT="$SIGLIP_ROOT/textual"
                mkdir -p "$SIGLIP_VIS" "$SIGLIP_TXT"
                if [ ! -f "$SIGLIP_ROOT/config.json" ]; then
                  cp "${siglip256Root}/config.json" "$SIGLIP_ROOT/config.json"
                fi
                "$python_path" - <<'PY'
import json
from pathlib import Path

root = Path("/var/cache/immich/clip/ViT-L-16-SigLIP-256__webli")
cfg_path = root / "config.json"
out_path = root / "open_clip_config.json"
tmp_path = root / "open_clip_config.json.tmp"
cfg = json.loads(cfg_path.read_text())
tmp_path.write_text(json.dumps({"model_cfg": cfg}))
tmp_path.replace(out_path)
out_path.chmod(0o644)
PY
                if [ ! -f "$SIGLIP_VIS/model.onnx" ]; then
                  cp "${siglip256Root}/visual/model.onnx" "$SIGLIP_VIS/model.onnx"
                fi
                if [ ! -f "$SIGLIP_VIS/preprocess_cfg.json" ]; then
                  cp "${siglip256Root}/visual/preprocess_cfg.json" "$SIGLIP_VIS/preprocess_cfg.json"
                fi
                if [ ! -f "$SIGLIP_TXT/model.onnx" ]; then
                  cp "${siglip256Root}/textual/model.onnx" "$SIGLIP_TXT/model.onnx"
                fi
                if [ ! -f "$SIGLIP_TXT/tokenizer.json" ]; then
                  cp "${siglip256Root}/textual/tokenizer.json" "$SIGLIP_TXT/tokenizer.json"
                fi
                if [ ! -f "$SIGLIP_TXT/tokenizer_config.json" ]; then
                  cp "${siglip256Root}/textual/tokenizer_config.json" "$SIGLIP_TXT/tokenizer_config.json"
                fi
                if [ ! -f "$SIGLIP_TXT/special_tokens_map.json" ]; then
                  cp "${siglip256Root}/textual/special_tokens_map.json" "$SIGLIP_TXT/special_tokens_map.json"
                fi
                chown -R immich:immich "$SIGLIP_ROOT"

                # Convert CLIP ONNX models to OpenVINO IR for GPU.
                tmp_py_clip="$(mktemp)"
                cat > "$tmp_py_clip" <<'PY'
import inspect
import faulthandler
import json
import os
from pathlib import Path

import onnx
try:
    from openvino import serialize
except Exception:  # pragma: no cover
    from openvino.runtime import serialize
from openvino.tools.ovc import convert_model

try:
    import torch
    import open_clip
    _HAS_OPEN_CLIP = True
except Exception:
    _HAS_OPEN_CLIP = False

faulthandler.enable()
cache_root = Path(os.environ.get("MACHINE_LEARNING_CACHE_FOLDER", "/var/cache/immich"))
clip_root = cache_root / "clip"
ov_root = cache_root / "ov" / "clip"

def load_json(path: Path) -> dict:
    return json.loads(path.read_text()) if path.exists() else {}

def infer_context_length(model_dir: Path) -> int:
    cfg = load_json(model_dir / "config.json")
    text_cfg = cfg.get("text_cfg") or {}
    return int(text_cfg.get("context_length", 77))

def infer_image_size(model_dir: Path) -> int:
    cfg = load_json(model_dir / "visual" / "preprocess_cfg.json")
    if not cfg:
        cfg = load_json(model_dir / "preprocess_cfg.json")
    size = cfg.get("size")
    if size is None:
        model_cfg = load_json(model_dir / "config.json")
        vision_cfg = model_cfg.get("vision_cfg") or {}
        size = vision_cfg.get("image_size", 224)
    return int(size[0] if isinstance(size, list) else size)

def infer_input_shapes(onnx_path: Path, model_dir: Path, kind: str) -> list[tuple[str, list[int]]]:
    model = onnx.load(onnx_path.as_posix())
    shapes = []
    if kind == "visual":
        size = infer_image_size(model_dir)
        shape = [1, 3, size, size]
        name = model.graph.input[0].name
        shapes.append((name, shape))
        return shapes
    context_len = infer_context_length(model_dir)
    for inp in model.graph.input:
        name = inp.name
        shape = [1, context_len]
        shapes.append((name, shape))
    return shapes

def convert_onnx(onnx_path: Path, model_dir: Path, out_dir: Path, kind: str) -> bool:
    out_dir.mkdir(parents=True, exist_ok=True)
    ov_xml = out_dir / "model.xml"
    ov_bin = out_dir / "model.bin"
    if ov_xml.exists() and ov_bin.exists():
        return True
    shapes = infer_input_shapes(onnx_path, model_dir, kind)
    kwargs = {"input": shapes}
    if "framework" in inspect.signature(convert_model).parameters:
        kwargs["framework"] = "onnx"
    ov_model = convert_model(onnx_path.as_posix(), **kwargs)
    serialize(ov_model, ov_xml.as_posix(), ov_bin.as_posix())
    print(f"converted clip {kind}: {ov_xml}")
    return True

def _parse_model_name(model_dir: Path) -> tuple[str, str] | None:
    if "__" not in model_dir.name:
        return None
    model_name, pretrained = model_dir.name.split("__", 1)
    return model_name, pretrained

def convert_open_clip(model_dir: Path, out_dir: Path, kind: str) -> bool:
    if not _HAS_OPEN_CLIP:
        print(f"open_clip not available, cannot convert {model_dir.name} {kind}")
        return False
    parsed = _parse_model_name(model_dir)
    if not parsed:
        print(f"cannot parse model name for {model_dir.name}")
        return False
    model_name, pretrained = parsed
    out_dir.mkdir(parents=True, exist_ok=True)
    ov_xml = out_dir / "model.xml"
    ov_bin = out_dir / "model.bin"
    fail_marker = out_dir / "model.failed"
    if fail_marker.exists():
        print(f"open_clip skipped (previous failure): {model_dir.name} {kind}")
        return False
    if ov_xml.exists() and ov_bin.exists():
        return True
    print(f"open_clip convert start: {model_dir.name} {kind}")

    cache_root = Path(os.environ.get("MACHINE_LEARNING_CACHE_FOLDER", "/var/cache/immich"))
    os.environ.setdefault("OPENCLIP_CACHE_DIR", str(cache_root / "open_clip"))
    os.environ.setdefault("HF_HOME", str(cache_root / "hf"))

    image_size = infer_image_size(model_dir)
    context_len = infer_context_length(model_dir)
    if model_dir.exists():
        model_id = f"local-dir:{model_dir.as_posix()}"
        pretrained_id = None
    else:
        model_id = model_name
        pretrained_id = pretrained
    print(f"open_clip create_model start: {model_id} pretrained={pretrained_id} image_size={image_size} context_len={context_len}")
    try:
        model, _, _ = open_clip.create_model_and_transforms(
            model_id,
            pretrained=pretrained_id,
            force_image_size=image_size,
            force_context_length=context_len,
        )
        model.eval()
    except Exception as e:
        print(f"open_clip create_model failed: {e}")
        try:
            fail_marker.write_text(str(e))
        except Exception:
            pass
        raise
    print("open_clip create_model done")

    if kind == "visual":
        example = torch.zeros(1, 3, image_size, image_size, dtype=torch.float32)
        print(f"open_clip visual ready: image_size={image_size}")
        try:
            print("open_clip trace_model start")
            scripted = open_clip.trace_model(model, batch_size=1)
            print("open_clip trace_model done")
            visual = scripted.visual
            print("openvino convert_model scripted visual start")
            ov_model = convert_model(visual, example_input=example)
            print("openvino convert_model scripted visual done")
        except Exception:
            wrapper = model.visual
            try:
                print("openvino convert_model raw visual start")
                ov_model = convert_model(wrapper, example_input=example)
                print("openvino convert_model raw visual done")
            except Exception:
                print("torch.jit.trace visual start")
                traced = torch.jit.trace(wrapper, example, strict=False)
                print("torch.jit.trace visual done")
                ov_model = convert_model(traced, example_input=example)
        try:
            ov_model.reshape({ov_model.inputs[0].any_name: [1, 3, image_size, image_size]})
        except Exception:
            pass
    else:
        class Textual(torch.nn.Module):
            def __init__(self, m):
                super().__init__()
                self.m = m
            def forward(self, text):
                return self.m.encode_text(text)
        wrapper = Textual(model)
        example = torch.zeros(1, context_len, dtype=torch.int64)
        ov_model = convert_model(wrapper, example_input=example)

    serialize(ov_model, ov_xml.as_posix(), ov_bin.as_posix())
    print(f"converted clip {kind} via open_clip: {ov_xml}")
    return True

if clip_root.exists():
    for model_dir in clip_root.iterdir():
        if not model_dir.is_dir():
            continue
        for kind in ("visual", "textual"):
            onnx_path = model_dir / kind / "model.onnx"
            out_dir = ov_root / model_dir.name / kind
            # Visual ONNX conversion is flaky for CLIP; use open_clip export instead.
            if kind == "visual":
                try:
                    convert_open_clip(model_dir, out_dir, kind)
                except Exception as e:
                    print(f"clip {model_dir.name} {kind} open_clip conversion failed: {e}")
                    try:
                        (out_dir / "model.failed").write_text(str(e))
                    except Exception:
                        pass
                continue
            if onnx_path.exists():
                try:
                    ok = convert_onnx(onnx_path, model_dir, out_dir, kind)
                except Exception as e:
                    ok = False
                    print(f"clip {model_dir.name} {kind} conversion failed: {e}")
                if not ok:
                    try:
                        convert_open_clip(model_dir, out_dir, kind)
                    except Exception as e:
                        print(f"clip {model_dir.name} {kind} open_clip conversion failed: {e}")
            else:
                try:
                    convert_open_clip(model_dir, out_dir, kind)
                except Exception as e:
                    print(f"clip {model_dir.name} {kind} open_clip conversion failed: {e}")
PY

                env -i PYTHON_PATH="$python_path" ENV_FILE="$tmp_env" PYTHONUNBUFFERED=1 PYTHONFAULTHANDLER=1 sh -c '
                  set -eu
                  . "$ENV_FILE"
                  "$PYTHON_PATH" "$0"
                ' "$tmp_py_clip" >> "$LOG" 2>&1 || true

                rm -f "$tmp_py_clip"

                # Convert ArcFace recognition ONNX to OpenVINO IR (static shape) for GPU.
                RECOG_DIR="/var/cache/immich/facial-recognition/buffalo_l/recognition"
                RECOG_ONNX="$RECOG_DIR/model.onnx"
                RECOG_OV_DIR="/var/cache/immich/ov/buffalo_l/recognition"
                RECOG_XML="$RECOG_OV_DIR/model.xml"
                RECOG_BIN="$RECOG_OV_DIR/model.bin"

                if [ -f "$RECOG_ONNX" ] && [ ! -f "$RECOG_XML" ]; then
                  tmp_py_rec="$(mktemp)"
                  cat > "$tmp_py_rec" <<'PY'
import os
from pathlib import Path

import onnx
try:
    from openvino import serialize
except Exception:  # pragma: no cover - fallback
    from openvino.runtime import serialize
from openvino.tools.ovc import convert_model

onnx_path = Path(os.environ["RECOG_ONNX"])
ov_xml = Path(os.environ["RECOG_XML"])
ov_bin = Path(os.environ["RECOG_BIN"])
ov_xml.parent.mkdir(parents=True, exist_ok=True)

model = onnx.load(onnx_path.as_posix())
inp = model.graph.input[0]
dims = inp.type.tensor_type.shape.dim
name = inp.name

def dim_value(d, default):
    return int(d.dim_value) if d.dim_value and d.dim_value > 0 else default

c = dim_value(dims[1], 3)
h = dim_value(dims[2], 112)
w = dim_value(dims[3], 112)
shape = [1, c, h, w]

try:
    ov_model = convert_model(onnx_path.as_posix(), input=[(name, shape)])
    serialize(ov_model, ov_xml.as_posix(), ov_bin.as_posix())
    print(f"converted recognition to IR: {ov_xml} shape={shape}")
except Exception as e:
    print(f"conversion failed: {e}")
PY

                  env -i PYTHON_PATH="$python_path" ENV_FILE="$tmp_env" RECOG_ONNX="$RECOG_ONNX" RECOG_XML="$RECOG_XML" RECOG_BIN="$RECOG_BIN" sh -c '
                    set -eu
                    . "$ENV_FILE"
                    "$PYTHON_PATH" "$0"
                  ' "$tmp_py_rec" >> "$LOG" 2>&1 || true

                  rm -f "$tmp_py_rec"
                fi

                [ -f "$MODEL" ] || { echo "model missing: $MODEL" >> "$LOG"; rm -f "$tmp_env"; exit 0; }
                [ -f "$ORIGINAL" ] && { echo "already patched: $ORIGINAL exists" >> "$LOG"; rm -f "$tmp_env"; exit 0; }

                {
                  echo "MODEL=$MODEL"
                  echo "STATIC=$STATIC"
                  echo "ORIGINAL=$ORIGINAL"
                  echo "PYTHON_PATH=$python_path"
                } >> "$LOG"

                tmp_py="$(mktemp)"
                cat > "$tmp_py" <<'PY'
import os
import onnx
import onnxruntime as ort

model_path = os.environ["MODEL"]
static_path = os.environ["STATIC"]
orig_path = os.environ["ORIGINAL"]

m = onnx.load(model_path)
inputs = m.graph.input
if not inputs:
    raise SystemExit(0)

inp = inputs[0]
dims = inp.type.tensor_type.shape.dim

def is_dynamic(dim):
    return (dim.dim_param != "") or (dim.dim_value == 0)

if not any(is_dynamic(d) for d in dims):
    raise SystemExit(0)

# Force static shape [1, 3, 640, 640]
target = [1, 3, 640, 640]
for i, d in enumerate(dims[:4]):
    d.dim_value = target[i]
    if d.HasField("dim_param"):
        d.ClearField("dim_param")

onnx.save(m, static_path)

# Preserve original once
if not os.path.exists(orig_path):
    os.rename(model_path, orig_path)

os.replace(static_path, model_path)
print("rewritten to static 640x640")

# Verify what ORT sees after rewrite
s = ort.InferenceSession(model_path, providers=["CPUExecutionProvider"])
print("ORT input shape:", s.get_inputs()[0].shape)
PY

                env -i PYTHON_PATH="$python_path" ENV_FILE="$tmp_env" MODEL="$MODEL" STATIC="$STATIC" ORIGINAL="$ORIGINAL" sh -c '
                  set -eu
                  . "$ENV_FILE"
                  "$PYTHON_PATH" "$0"
                ' "$tmp_py" >> "$LOG" 2>&1

                rm -f "$tmp_py"

                rm -f "$tmp_env"
                ls -l "$MODEL_DIR" >> "$LOG" 2>&1 || true
              '';

              # Run PostgreSQL as the immich user so it has access to the bind-mounted data directory
              systemd.services.postgresql.serviceConfig = {
                User = lib.mkForce "immich";
                Group = lib.mkForce "immich";
              };

              # Ensure runtime directory for postgres is owned by immich
              systemd.tmpfiles.rules = [
                "d /run/postgresql 0755 immich immich -"
              ];

              systemd.services.immich-clip-index = {
                description = "Ensure smart_search vchord index settings";
                wantedBy = [ "immich-server.service" ];
                before = [ "immich-server.service" ];
                after = [ "postgresql.service" ];
                requires = [ "postgresql.service" ];
                serviceConfig = {
                  Type = "oneshot";
                  User = "immich";
                  Group = "immich";
                };
                script = ''
                  idxdef="$(
                    psql -d immich -t -A -c \
                      "select indexdef from pg_indexes where tablename='smart_search' and indexname='clip_index';"
                  )"
                  need_rebuild=1
                  if [ -n "$idxdef" ] \
                    && echo "$idxdef" | grep -q "vchordrq" \
                    && echo "$idxdef" | grep -q "lists = \\[128\\]" \
                    && echo "$idxdef" | grep -q "sampling_factor = 1024"; then
                    need_rebuild=0
                  fi
                  if [ "$need_rebuild" -eq 1 ]; then
                    psql -d immich -v ON_ERROR_STOP=1 <<'SQL'
DROP INDEX IF EXISTS clip_index;
CREATE INDEX clip_index ON smart_search
USING vchordrq (embedding vector_cosine_ops)
WITH (options = $opts$
residual_quantization = false
[build.internal]
lists = [128]
spherical_centroids = true
build_threads = 4
sampling_factor = 1024
$opts$);
SQL
                  fi
                '';
              };

              systemd.services.immich-init-markers = {
                description = "Create Immich marker files for mount verification";
                wantedBy = [ "immich-server.service" ];
                before = [ "immich-server.service" ];
                serviceConfig = {
                  Type = "oneshot";
                  RemainAfterExit = true;
                  User = "immich";
                  Group = "immich";
                };
                script = ''
                  for dir in encoded-video thumbs upload library profile backups; do
                    marker="${immichMedia}/$dir/.immich"
                    if [[ ! -f "$marker" ]]; then
                      touch "$marker"
                    fi
                  done
                '';
              };

              users.users.immich = {
                isSystemUser = true;
                inherit (cfg) uid;
                group = "immich";
                home = "/var/lib/immich";
                extraGroups = lib.optionals cfg.gpu.enable [
                  "video"
                  "render"
                ];
              };
              users.groups.immich.gid = cfg.gid;
            }
          ];
        };
      }
    ]
  );
}
