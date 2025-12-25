{ lib, inputs, ... }:
{
  # use path relative to the root of the project
  relativeToRoot = lib.path.append ../.;

  # Storage helper functions for btrfs + disko + snapraid
  storage = import ./storage.nix { inherit lib; };

  scanPaths =
    path:
    builtins.map (f: (path + "/${f}")) (
      builtins.attrNames (
        lib.attrsets.filterAttrs (
          path: _type:
          (_type == "directory") # include directories
          || (
            (path != "default.nix") # ignore default.nix
            && (lib.strings.hasSuffix ".nix" path) # include .nix files
          )
        ) (builtins.readDir path)
      )
    );

  # Helper to generate container network configuration
  # Usage: lib.custom.mkContainerNetworkConfig config "arr" "mycontainer"
  mkContainerNetworkConfig =
    config: networkName: containerName:
    let
      networkCfg = config.hostSpec.networking.containerNetworks.${networkName};
      subnetParts = lib.splitString "/" networkCfg.subnet;
      subnetBase = builtins.elemAt subnetParts 0;
      cidr = builtins.elemAt subnetParts 1;
      prefixParts = lib.init (lib.splitString "." subnetBase);

      mkIP =
        value:
        if lib.isString value then
          value
        else
          lib.concatStringsSep "." (prefixParts ++ [ (builtins.toString value) ]);
    in
    {
      inherit networkCfg cidr;
      containerIP = mkIP networkCfg.containers.${containerName};
      gatewayIP = mkIP networkCfg.gateway;
      bridge = networkCfg.bridge;
    };

  # Common container base config with networking and DNS
  mkContainerBaseConfig =
    {
      containerIP,
      gatewayIP,
      cidr,
      domain ? "",
      stateVersion ? "25.05",
      ...
    }:
    {
      system.stateVersion = stateVersion;

      networking.interfaces.eth0.useDHCP = false;
      networking.defaultGateway = gatewayIP;

      # Override resolv.conf directly to avoid systemd-resolved conflicts
      # TODO: Use host's Unbound DNS (config.hostSpec.networking.localIP) instead of external DNS
      # This would enable split-horizon DNS and ad-blocking for containers
      environment.etc."resolv.conf".text = ''
        nameserver 1.1.1.1
        nameserver 8.8.8.8
        ${lib.optionalString (domain != "") "search ${domain}"}
      '';

      # Disable services that might interfere with DNS
      networking.resolvconf.enable = false;
      services.resolved.enable = false;
    };

  # Helper to generate host-level systemd service configuration for containers
  # Usage: lib.custom.mkContainerSystemd "mycontainer" { dependsOn = [ "container1" "container2" ]; }
  mkContainerSystemd =
    containerName:
    {
      dependsOn ? [ ],
    }:
    {
      services."container@${containerName}" = {
        wants = [ "network-online.target" ] ++ (map (dep: "container@${dep}.service") dependsOn);
        after = [
          "network-online.target"
          "systemd-tmpfiles-setup.service"
        ]
        ++ (map (dep: "container@${dep}.service") dependsOn);
      };
    };

  # Helper to create container storage directories via activation scripts
  # Usage: lib.custom.mkContainerDirs "mycontainer" [ "/mnt/storage/mycontainer" "/mnt/storage/mycontainer/data" ]
  # Or with custom ownership: lib.custom.mkContainerDirs "mycontainer" [ { path = "/mnt/storage/foo"; owner = "myuser"; group = "mygroup"; mode = "0750"; } ]
  #
  # This runs on every activation and ensures directories exist with correct ownership/permissions.
  # If ownership/permissions change in config, they will be updated on next rebuild.
  mkContainerDirs =
    containerName: dirs:
    let
      # Normalize directories to always have path, owner, group, mode
      normalizeDirs = builtins.map (
        d:
        if builtins.isString d then
          {
            path = d;
            owner = "root";
            group = "root";
            mode = "0755";
          }
        else
          {
            path = d.path;
            owner = d.owner or "root";
            group = d.group or "root";
            mode = d.mode or "0755";
          }
      ) dirs;

      # Generate commands that create AND update directories
      setupCmds = lib.concatMapStringsSep "\n" (d: ''
        mkdir -p ${d.path}
        chown ${d.owner}:${d.group} ${d.path}
        chmod ${d.mode} ${d.path}
      '') normalizeDirs;
    in
    {
      system.activationScripts."mkDirs-${containerName}" = lib.stringAfter [ "var" ] ''
        # Create/update directories for ${containerName} container
        # Runs on every activation to ensure correct ownership and permissions
        ${setupCmds}
      '';
    };
}
