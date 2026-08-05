# sudo systemd-run -t --pty -M immich --uid=immich \
#     /run/current-system/sw/bin/bash
#
# To try if the hardware acceleration works
# ffmpeg -hide_banner \
#  -init_hw_device qsv=hw:/dev/dri/renderD128 \
#  -f lavfi -i testsrc=size=128x128:rate=1 -t 1 \
#  -c:v h264_qsv -f null -
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

# Excellent inspiration:
# https://blog.beardhatcode.be/2020/12/Declarative-Nixos-Containers.html?utm_source=chatgpt.com
# https://msucharski.eu/posts/application-isolation-nixos-containers/
{
  imports = [
    (./networking.nix)
  ];

  # Create immich user and group on host to match container UID/GID
  # The NixOS immich module auto-assigns UID/GID (currently 999), so we match it on the host
  # This ensures bind-mounted directories have correct ownership across host/container boundary
  #
  # To verify the container UID/GID: sudo machinectl shell immich /run/current-system/sw/bin/id immich
  # To check for conflicts: getent passwd | awk -F: '$3 == 999 {print}'
  users.users.immich = {
    isSystemUser = true;
    group = "immich";
    uid = 999;
  };
  users.groups.immich = {
    gid = 999;
  };

  custom.reverseProxy.virtualHosts.immich = {
    domain = "immich.${config.hostSpec.domain}";
    backendHost = "10.0.0.2";
    backendPort = 2283;
    backendSSL = false;
  };

  # OIDC client secret for Kanidm OAuth2
  sops.secrets."immich/oidc-client-secret" = {
    sopsFile = "${builtins.toString inputs.nix-secrets}/sops/shared.yaml";
    owner = "root";
    group = "kanidm";
    mode = "0440";
  };

  # OAuth2 client registration (consumed by kanidm.nix)
  custom.kanidm.oauthClients.immich = {
    displayName = "Immich";
    originUrl = [
      "https://immich.${config.hostSpec.domain}/auth/login"
      "https://immich.${config.hostSpec.domain}/api/oauth/mobile-redirect"
      "https://immich.${config.hostSpec.domain}/user-settings"
      "app.immich:///oauth-callback"
      "app.immich://oauth-callback"
      "app.immich:/oauth-callback"
      "com.alextran.immich://oauth-callback"
    ];
    originLanding = "https://immich.${config.hostSpec.domain}/";
    secretFile = config.sops.secrets."immich/oidc-client-secret".path;
    enableLegacyCrypto = true; # Immich still uses RS256 instead of ES256
    scopeMap.immich_users = [
      "openid"
      "email"
      "profile"
    ];
  };

  hostSpec.networking.containerNetworks.immich.bridge = lib.mkDefault "immich-bridge";
  hostSpec.networking.containerNetworks.immich.subnet = lib.mkDefault "10.0.0.0/24";
  hostSpec.networking.containerNetworks.immich.gateway = lib.mkDefault "10.0.0.1";
  hostSpec.networking.containerNetworks.immich.containers.immich = lib.mkDefault 2;

  containers.immich =
    let
      net = lib.custom.mkContainerNetworkConfig config "immich" "immich";
      immichMedia = "/var/lib/immich";
      hostConfig = config;
      immichUid = toString config.users.users.immich.uid;
      immichGid = toString config.users.groups.immich.gid;
    in
    {
      autoStart = true;

      bindMounts = {
        "${immichMedia}" = {
          hostPath = "/mnt/storage/immich";
          isReadOnly = false;
        };
        # Pass the render device to the container
        "/dev/dri" = {
          hostPath = "/dev/dri";
          isReadOnly = false;
        };
        # Mount SOPS secrets
        "/run/secrets" = {
          hostPath = "/run/secrets";
          isReadOnly = true;
        };
      };
      allowedDevices = [
        # Give the container R/W access to render devices
        {
          node = hostConfig.hostSpec.gpu.renderDevice;
          modifier = "rwm";
        }
        {
          node = hostConfig.hostSpec.gpu.cardDevice;
          modifier = "rwm";
        }
      ];

      privateNetwork = true; # Gives the container its own virtual ethernet interface ve-immich
      hostBridge = net.bridge;
      localAddress = "${net.containerIP}/${net.cidr}";

      forwardPorts = [
        {
          hostPort = 2283;
          containerPort = 2283;
        }
      ];

      config = lib.mkMerge [
        (lib.custom.mkContainerBaseConfig (net // { inherit (config.hostSpec) stateVersion; }))
        {
          # https://wiki.nixos.org/wiki/Jellyfin#Troubleshooting_VAAPI_and_Intel_QSV
          # Probably not needed for immich graphics but kept for example
          environment.sessionVariables = {
            LIBVA_DRIVER_NAME = "iHD";
          };
          # Graphics needs to be explicitly enabled inside containers and we need to enable the required drivers
          # Just enable everything from host side if you are lazy
          hardware.graphics = {
            enable = true;
            extraPackages = hostConfig.hardware.graphics.extraPackages ++ [
              pkgs.intel-compute-runtime
              pkgs.intel-media-driver
              pkgs.intel-ocl
              pkgs.ocl-icd
              pkgs.level-zero
              pkgs.intel-vaapi-driver
            ];
          };

          services.immich = {
            enable = true;
            database.enable = true;
            host = net.containerIP;
            openFirewall = true;
            mediaLocation = immichMedia;
            # You have to explicitly specify what device immich should use for hw-accel
            accelerationDevices = [ hostConfig.hostSpec.gpu.renderDevice ];
            environment = {
              TZ = "Europe/Stockholm";
            };
            machine-learning.enable = true;
            machine-learning.environment = {
              MACHINE_LEARNING_WORKERS = "1";
              MACHINE_LEARNING_MAX_BATCH_SIZE__FACIAL_RECOGNITION = "1";
              MACHINE_LEARNING_MAX_BATCH_SIZE__CLIP = "1";
              MACHINE_LEARNING_MAX_BATCH_SIZE__OCR = "1";
              MACHINE_LEARNING_OPENVINO_PRECISION = "FP16";
              MACHINE_LEARNING_WORKER_TIMEOUT = "300";
              MACHINE_LEARNING_CACHE_FOLDER = "/var/cache/immich";
              OPENVINO_DEVICE = "GPU,GPU_FP16,GPU.0";
              MACHINE_LEARNING_DEVICE_IDS = "0";
              OPENVINO_PERFORMANCE_HINT = "LATENCY";
              ONNXRUNTIME_OPENVINO_ENABLE_DYNAMIC_SHAPES = "0";
              # Explicit OpenCL ICD path for containers (no /etc/OpenCL/vendors).
              OCL_ICD_VENDORS = "${pkgs.intel-compute-runtime}/etc/OpenCL/vendors";
              OPENCL_VENDOR_PATH = "${pkgs.intel-compute-runtime}/etc/OpenCL/vendors";
              OV_GPU_CACHE_DIR = "/var/cache/immich";
              OV_GPU_ENABLE_PROPERTIES = "CACHE_DIR=/var/cache/immich";
              ORT_LOG_LEVEL = "VERBOSE";
              OV_LOG_LEVEL = "DEBUG";
              # Ensure OpenVINO Python module is on the service PYTHONPATH
              PYTHONPATH = "${pkgs.python3Packages.openvino}/${pkgs.python3.sitePackages}";
            };
            # NOTE: This will just override the default values in immich-config.json
            # See https://immich.app/docs/install/config-file/
            settings = {
              backup.database.enabled = false; # TODO: Setup some actaul database backup using borg
              ffmpeg = {
                accel = "qsv";
                accelDecode = true;
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
              passwordLogin = {
                enabled = false; # Disable password login when OIDC is enabled
              };
              server = {
                externalDomain = "https://${hostConfig.custom.reverseProxy.virtualHosts.immich.domain}";
              };
            };
          };
          # Patch InsightFace RetinaFace ONNX to static shape for OpenVINO GPU.
          systemd.services.immich-machine-learning.preStart = lib.mkBefore ''
            set -eu
            set -x

            LOG="/var/cache/immich/prestart.log"
            echo "=== preStart $(date -Is) ===" >> "$LOG"

            MODEL_DIR="/var/cache/immich/facial-recognition/buffalo_l/detection"
            MODEL="$MODEL_DIR/model.onnx"
            STATIC="$MODEL_DIR/model.static.onnx"
            ORIGINAL="$MODEL_DIR/model.dynamic.onnx"

            [ -f "$MODEL" ] || { echo "model missing: $MODEL" >> "$LOG"; exit 0; }

            ml="$(systemctl show -p ExecStart --value immich-machine-learning | sed -n "s/.*path=\\([^ ;]*\\).*/\\1/p")"
            gunicorn="$(grep -oE "/nix/store/[^\"[:space:]]+-gunicorn-[^\"[:space:]]+/bin/gunicorn" "$ml" | head -n1)"
            wrapped="$(grep -oE "/nix/store/[^\"[:space:]]+/bin/\\.gunicorn-wrapped" "$gunicorn" | head -n1)"
            python_path="$(sed -n "1{s/^#![[:space:]]*//;s/[[:space:]].*$//;p}" "$wrapped")"

            tmp_env="$(mktemp)"
            {
              awk "/^PATH=|^export PATH|^export PYTHONNOUSERSITE/ {print}" "$gunicorn"
              awk "/^PYTHONPATH=|^export PYTHONPATH/ {print}" "$ml"
            } > "$tmp_env"

            env -i PYTHON_PATH="$python_path" ENV_FILE="$tmp_env" MODEL="$MODEL" STATIC="$STATIC" ORIGINAL="$ORIGINAL" sh -c "
              set -eu
              . \"\$ENV_FILE\"
              \"\$PYTHON_PATH\" - <<'PY'
import os
import onnx

model_path = os.environ['MODEL']
static_path = os.environ['STATIC']
orig_path = os.environ['ORIGINAL']

m = onnx.load(model_path)
inputs = m.graph.input
if not inputs:
    raise SystemExit(0)

inp = inputs[0]
dims = inp.type.tensor_type.shape.dim

def is_dynamic(dim):
    return (dim.dim_param != '') or (dim.dim_value == 0)

if not any(is_dynamic(d) for d in dims):
    raise SystemExit(0)

# Force static shape [1, 3, 640, 640]
target = [1, 3, 640, 640]
for i, d in enumerate(dims[:4]):
    d.dim_value = target[i]
    d.dim_param = ''

onnx.save(m, static_path)

# Preserve original once
if not os.path.exists(orig_path):
    os.rename(model_path, orig_path)

os.replace(static_path, model_path)
print('rewritten to static 640x640')
PY
            "

            rm -f "$tmp_env"
            ls -l "$MODEL_DIR" >> "$LOG" 2>&1 || true
          '';

          # Create .immich marker files that Immich requires for mount verification
          # See https://docs.immich.app/administration/system-integrity#folder-checks
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

          # Add immich user to video and render groups for GPU access
          users.users.immich.extraGroups = [
            "video"
            "render"
          ];
        }
      ];
    };

  systemd = lib.mkMerge [
    (lib.custom.mkContainerSystemd "immich" { })
  ];

}
// (
  let
    immichUid = toString config.users.users.immich.uid;
    immichGid = toString config.users.groups.immich.gid;
  in
  lib.custom.mkContainerDirs "immich" [
    {
      path = "/mnt/storage/immich";
      owner = immichUid;
      group = immichGid;
      mode = "0755";
    }
    {
      path = "/mnt/storage/immich/encoded-video";
      owner = immichUid;
      group = immichGid;
      mode = "0755";
    }
    {
      path = "/mnt/storage/immich/thumbs";
      owner = immichUid;
      group = immichGid;
      mode = "0755";
    }
    {
      path = "/mnt/storage/immich/upload";
      owner = immichUid;
      group = immichGid;
      mode = "0755";
    }
    {
      path = "/mnt/storage/immich/library";
      owner = immichUid;
      group = immichGid;
      mode = "0755";
    }
    {
      path = "/mnt/storage/immich/profile";
      owner = immichUid;
      group = immichGid;
      mode = "0755";
    }
    {
      path = "/mnt/storage/immich/backups";
      owner = immichUid;
      group = immichGid;
      mode = "0755";
    }
  ]
)
