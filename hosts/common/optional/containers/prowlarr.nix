# Prowlarr indexer management container
{
  config,
  pkgs,
  lib,
  ...
}:

let
  uid = 10700;
  gid = 10700;
in
{
  imports = [
    (./networking.nix)
  ];

  # --- Host user/group (matches container for bind mount ownership) ---
  users.users.prowlarr = {
    isSystemUser = true;
    group = "prowlarr";
    inherit uid;
  };
  users.groups.prowlarr.gid = gid;

  hostSpec.networking.containerNetworks.arr.bridge = lib.mkDefault "arr-bridge";
  hostSpec.networking.containerNetworks.arr.subnet = lib.mkDefault "10.0.1.0/24";
  hostSpec.networking.containerNetworks.arr.gateway = lib.mkDefault "10.0.1.1";
  hostSpec.networking.containerNetworks.arr.containers.prowlarr = lib.mkDefault 6;

  systemd.tmpfiles.rules = [
    "d /mnt/storage/prowlarr 0755 ${toString uid} ${toString gid} -"
  ];

  containers.prowlarr =
    let
      net = lib.custom.mkContainerNetworkConfig config "arr" "prowlarr";
    in
    {
      autoStart = true;

      bindMounts = {
        "/var/lib/prowlarr" = {
          hostPath = "/mnt/storage/prowlarr";
          isReadOnly = false;
        };
      };

      privateNetwork = true;
      hostBridge = net.bridge;
      localAddress = "${net.containerIP}/${net.cidr}";

      forwardPorts = [
        {
          hostPort = 9696;
          containerPort = 9696;
        }
      ];

      config = lib.mkMerge [
        (lib.custom.mkContainerBaseConfig net)
        {
          systemd.services.prowlarr = {
            enable = true;
            description = "Prowlarr indexer manager";
            after = [ "network.target" ];
            wantedBy = [ "multi-user.target" ];

            serviceConfig = {
              Type = "exec";
              User = "prowlarr";
              Group = "prowlarr";
              ExecStart = "${pkgs.prowlarr}/bin/Prowlarr -nobrowser -data=/var/lib/prowlarr";
              Restart = "on-failure";
              WorkingDirectory = "/var/lib/prowlarr";
            };
          };

          # --- Container user/group (matches host) ---
          users.users.prowlarr = {
            isSystemUser = true;
            inherit uid;
            group = "prowlarr";
            home = "/var/lib/prowlarr";
          };
          users.groups.prowlarr.gid = gid;

          networking.firewall.allowedTCPPorts = [ 9696 ];

          systemd.tmpfiles.rules = [
            "d /var/lib/prowlarr 0755 ${toString uid} ${toString gid} -"
          ];
        }
      ];
    };

  systemd.services."container@prowlarr" = {
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "systemd-tmpfiles-setup.service"
    ];
  };
}
