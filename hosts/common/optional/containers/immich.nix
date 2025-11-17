# sudo systemd-run -t --pty -M immich --uid=immich \
#     /run/current-system/sw/bin/bash
#
# To try if the hard-ware acceleration works (must be as immich):
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

  hostSpec.domains.immich = {
    domain = "immich.${config.hostSpec.domain}";
    public = true;
    backendHost = "10.0.0.2";
    backendPort = 2283;
    backendSSL = false;
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
        (lib.custom.mkContainerBaseConfig net)
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
            extraPackages = hostConfig.hardware.graphics.extraPackages;
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
            # NOTE: This will just override the default values in immich-config.json
            # See https://immich.app/docs/install/config-file/
            secretSettings.oauth.clientSecret = hostConfig.sops.secrets."immich/oidc-client-secret".path;
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
                issuerUrl = "https://auth.${config.hostSpec.domain}/oauth2/openid/immich";
                scope = "openid profile email";
                signingAlgorithm = "RS256";

                mobileRedirectUri = "app.immich:///oauth-callback";
              };
              passwordLogin = {
                enabled = false; # Disable password login when OIDC is enabled
              };
              server = {
                externalDomain = "https://${hostConfig.hostSpec.domains.immich.domain}";
              };
            };
          };

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
