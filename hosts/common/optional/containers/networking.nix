{
  config,
  lib,
  ...
}:

let
  rawContainerNetworks = lib.attrByPath [ "hostSpec" "networking" "containerNetworks" ] { } config;

  parseHostValue =
    value:
    if lib.isInt value then
      {
        hostId = value;
        explicitIP = null;
      }
    else if builtins.match "^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$" value != null then
      let
        octets = lib.splitString "." value;
        hostOctet = builtins.elemAt octets ((builtins.length octets) - 1);
      in
      {
        hostId = builtins.fromJSON hostOctet;
        explicitIP = value;
      }
    else
      {
        hostId = builtins.fromJSON value;
        explicitIP = null;
      };

  resolvedNetworksData = lib.mapAttrs (
    name: cfg:
    let
      subnetParts = lib.splitString "/" cfg.subnet;
      subnetBase = builtins.elemAt subnetParts 0;
      cidr = builtins.elemAt subnetParts 1;
      prefixParts = lib.init (lib.splitString "." subnetBase);
      mkIP = hostId: lib.concatStringsSep "." (prefixParts ++ [ (builtins.toString hostId) ]);
      containerData = lib.mapAttrs (_: parseHostValue) cfg.containers;
      hostIds = lib.mapAttrs (_: data: data.hostId) containerData;
      containersResolved = lib.mapAttrs (
        _: data: if data.explicitIP != null then data.explicitIP else mkIP data.hostId
      ) containerData;
      gatewayData = parseHostValue cfg.gateway;
      gatewayIP =
        if gatewayData.explicitIP != null then gatewayData.explicitIP else mkIP gatewayData.hostId;
    in
    {
      resolved = cfg // {
        containers = containersResolved;
        gateway = gatewayIP;
      };
      hostIds = hostIds;
      gatewayHostId = gatewayData.hostId;
      cidr = cidr;
    }
  ) rawContainerNetworks;

  containerNetworks = lib.mapAttrs (_: data: data.resolved) resolvedNetworksData;
  hostIdsByNetwork = lib.mapAttrs (_: data: data.hostIds) resolvedNetworksData;
  gatewayHostIds = lib.mapAttrs (_: data: data.gatewayHostId) resolvedNetworksData;
  cidrByNetwork = lib.mapAttrs (_: data: data.cidr) resolvedNetworksData;

  bridges = lib.attrValues (lib.mapAttrs (_: cfg: cfg.bridge) containerNetworks);
  bridgeSet = lib.concatMapStringsSep "," (b: "\"${b}\"") bridges;
  gatewayIPs = lib.attrValues (lib.mapAttrs (_: cfg: cfg.gateway) containerNetworks);
  gatewayIPSet = lib.concatMapStringsSep "," (ip: "\"${ip}\"") gatewayIPs;
  subnets = lib.attrValues (lib.mapAttrs (_: cfg: cfg.subnet) containerNetworks);
  subnetSet = if subnets == [ ] then "0.0.0.0/32" else lib.concatStringsSep ", " subnets;
  privateRanges = ''{ 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 }'';

  countOccurrences =
    list:
    lib.foldl' (
      acc: item:
      let
        key = builtins.toString item;
      in
      acc // { ${key} = (acc.${key} or 0) + 1; }
    ) { } list;

  findDuplicates =
    list: lib.attrNames (lib.filterAttrs (_: count: count > 1) (countOccurrences list));

  bridgeDuplicates = findDuplicates bridges;
  subnetDuplicates = findDuplicates subnets;
  hostIdConflicts = lib.filterAttrs (_: duplicates: duplicates != [ ]) (
    lib.mapAttrs (_: hostMap: findDuplicates (lib.attrValues hostMap)) hostIdsByNetwork
  );
  invalidHostIds = lib.filterAttrs (_: entries: entries != { }) (
    lib.mapAttrs (
      _: hostMap: lib.filterAttrs (_: hostId: hostId <= 1 || hostId >= 255) hostMap
    ) hostIdsByNetwork
  );
  gatewayConflicts = lib.filterAttrs (_: entries: entries != { }) (
    lib.mapAttrs (
      name: hostMap:
      let
        gatewayId = gatewayHostIds.${name};
      in
      lib.filterAttrs (_: hostId: hostId == gatewayId) hostMap
    ) hostIdsByNetwork
  );
  cidrViolations = lib.filterAttrs (_: data: data.cidr != "24") resolvedNetworksData;

  formatAttrNames = attrs: lib.concatStringsSep ", " (lib.attrNames attrs);

  assertionsList = [
    {
      assertion = bridgeDuplicates == [ ];
      message =
        let
          text = lib.concatStringsSep ", " bridgeDuplicates;
        in
        "Duplicate container bridges detected: ${text}";
    }
    {
      assertion = subnetDuplicates == [ ];
      message =
        let
          text = lib.concatStringsSep ", " subnetDuplicates;
        in
        "Duplicate container subnets detected: ${text}";
    }
    {
      assertion = cidrViolations == { };
      message =
        let
          text = formatAttrNames cidrViolations;
        in
        "Only /24 container subnets are supported; fix networks: ${text}";
    }
    {
      assertion = hostIdConflicts == { };
      message =
        let
          text = formatAttrNames hostIdConflicts;
        in
        "Duplicate container host IDs per subnet: ${text}";
    }
    {
      assertion = invalidHostIds == { };
      message =
        let
          text = formatAttrNames invalidHostIds;
        in
        "Container host IDs must be between 2 and 254: ${text}";
    }
    {
      assertion = gatewayConflicts == { };
      message =
        let
          text = formatAttrNames gatewayConflicts;
        in
        "Container host IDs may not match the gateway: ${text}";
    }
  ];

  # Get configuration from hostSpec
  externalIfaces = config.hostSpec.networking.externalInterfaces or [ ];
  primaryIface = if externalIfaces != [ ] then builtins.elemAt externalIfaces 0 else "eth0";
  dnsServers = config.hostSpec.networking.dnsServers;

  # Reverse-lookup: for each container, find which network it belongs to
  containerToNetwork = lib.mapAttrs (
    containerName: _:
    let
      matchingNetworks = lib.filterAttrs (
        netName: netCfg: netCfg.containers ? ${containerName}
      ) containerNetworks;
    in
    if matchingNetworks == { } then null else lib.head (lib.attrNames matchingNetworks)
  ) config.containers;

  # Generate DNAT rules from container forwardPorts
  generateDNATRules =
    iface:
    lib.concatStrings (
      lib.mapAttrsToList (
        containerName: containerCfg:
        let
          networkName = containerToNetwork.${containerName};
        in
        if networkName == null then
          ""
        else
          let
            containerIP = containerNetworks.${networkName}.containers.${containerName};
          in
          lib.concatMapStrings (
            port:
            # Special case: DNS (port 53) needs both TCP and UDP
            if port.hostPort == 53 then
              ''
                iifname "${iface}" tcp dport ${toString port.hostPort} dnat ip to ${containerIP}:${toString port.containerPort}
                iifname "${iface}" udp dport ${toString port.hostPort} dnat ip to ${containerIP}:${toString port.containerPort}
              ''
            else
              ''
                iifname "${iface}" tcp dport ${toString port.hostPort} dnat ip to ${containerIP}:${toString port.containerPort}
              ''
          ) containerCfg.forwardPorts
      ) config.containers
    );

  # Generate forward rules from container forwardPorts
  generateForwardRules =
    iface:
    lib.concatStrings (
      lib.mapAttrsToList (
        containerName: containerCfg:
        let
          networkName = containerToNetwork.${containerName};
        in
        if networkName == null then
          ""
        else
          let
            containerIP = containerNetworks.${networkName}.containers.${containerName};
            bridge = containerNetworks.${networkName}.bridge;
          in
          lib.concatMapStrings (
            port:
            let
              # Special case: qbittorrent allows both external and lo
              ifaceRule = if containerName == "qbittorrent" then ''{ "${iface}", "lo" }'' else ''"${iface}"'';
            in
            # Special case: DNS (port 53) needs both TCP and UDP
            if port.hostPort == 53 then
              ''
                iifname ${ifaceRule} oifname "${bridge}" ip daddr ${containerIP} tcp dport ${toString port.containerPort} counter accept
                iifname ${ifaceRule} oifname "${bridge}" ip daddr ${containerIP} udp dport ${toString port.containerPort} counter accept
              ''
            else
              ''
                iifname ${ifaceRule} oifname "${bridge}" ip daddr ${containerIP} tcp dport ${toString port.containerPort} counter accept
              ''
          ) containerCfg.forwardPorts
      ) config.containers
    );

  # Collect all forwarded ports for firewall
  allForwardedPorts = lib.unique (
    lib.flatten (
      lib.mapAttrsToList (
        _: containerCfg: map (port: port.hostPort) containerCfg.forwardPorts
      ) config.containers
    )
  );

in
{
  config = {
    assertions = assertionsList ++ [
      {
        assertion = externalIfaces != [ ];
        message = "hostSpec.networking.externalInterfaces must be defined for container networking.";
      }
    ];
    # ================ Core Network Setup ================
    networking.useNetworkd = true;
    networking.useDHCP = false;
    networking.dhcpcd.enable = false;

    systemd.network = {
      enable = true;

      # Combined networks definition
      networks =
        # Main external interface(s)
        (lib.listToAttrs (
          lib.imap0 (idx: iface: {
            name = "10-${iface}";
            value = {
              matchConfig.Name = iface;
              networkConfig = {
                DHCP = "yes"; # Enable both IPv4 and IPv6
                DNS = dnsServers;
              };
              dhcpConfig = {
                UseDNS = false;
                UseDomains = false;
                RouteMetric = 100 + idx; # Primary has lower metric
              };
              linkConfig.RequiredForOnline = if idx == 0 then "routable" else "no";
            };
          }) externalIfaces
        ))
        //
          # Bridge interfaces
          (lib.mapAttrs' (_: cfg: {
            name = "40-${cfg.bridge}";
            value = {
              matchConfig.Name = cfg.bridge;
              address = [ "${cfg.gateway}/${lib.last (lib.splitString "/" cfg.subnet)}" ];
              networkConfig = {
                IPv4Forwarding = true;
                DNS = dnsServers;
              };
              linkConfig.RequiredForOnline = false;
            };
          }) containerNetworks);

      # Bridge netdevs
      netdevs = lib.mapAttrs' (_: cfg: {
        name = "30-${cfg.bridge}";
        value = {
          netdevConfig = {
            Name = cfg.bridge;
            Kind = "bridge";
          };
        };
      }) containerNetworks;
    };

    # ================ NAT & Firewall ================
    networking.nat = {
      enable = true;
      externalInterface = primaryIface;
      internalInterfaces = bridges;
    };

    networking.nftables = {
      enable = true;
      ruleset = ''
        table inet nixos-fw {
          chain prerouting {
            type nat hook prerouting priority dstnat; policy accept;

            # Container DNAT rules - auto-generated from forwardPorts
            ${lib.concatMapStrings (iface: generateDNATRules iface) (externalIfaces ++ [ "wg0" ])}
          }

          chain postrouting {
            type nat hook postrouting priority srcnat; policy accept;

            # SNAT for container traffic going to external networks
            ${lib.concatMapStrings (
              iface:
              lib.concatMapStrings (
                subnet: "          oifname \"${iface}\" ip saddr ${subnet} masquerade\n"
              ) subnets
            ) externalIfaces}

            # SNAT for WireGuard VPN traffic going to external networks and LAN
            ${lib.concatMapStrings (
              iface: "          oifname \"${iface}\" ip saddr 10.100.0.0/24 masquerade\n"
            ) externalIfaces}
          }

          chain forward {
            type filter hook forward priority filter; policy drop;

            # Allow established connections
            ct state established,related accept

            # Allow containers to reach internet via all external interfaces (but not other private networks)
            ${lib.concatMapStrings (
              iface: "          iifname { ${bridgeSet} } oifname \"${iface}\" accept\n"
            ) externalIfaces}

            # Block containers from accessing other private ranges (but allow their own subnets)
            iifname { ${bridgeSet} } ip daddr { 192.168.0.0/16, 172.16.0.0/12 } counter drop
            iifname { ${bridgeSet} } ip daddr 10.0.0.0/8 ip daddr != { ${subnetSet} } counter drop

            # Allow inter-container communication within same bridge
            iifname { ${bridgeSet} } oifname { ${bridgeSet} } accept

            # WireGuard VPN exceptions
            iifname "wg0" accept
            oifname "wg0" accept

            # Container port forwarding - auto-generated from forwardPorts
            ${lib.concatMapStrings (iface: generateForwardRules iface) (externalIfaces ++ [ "wg0" ])}
          }
        }
      '';
    };

    networking.firewall = {
      allowedTCPPorts = [
        22
        53
      ]
      ++ allForwardedPorts; # Auto-generate from forwardPorts
      allowedUDPPorts = [ 53 ];
      extraInputRules = ''
        # Allow WireGuard VPN traffic
        iifname "wg0" accept

        iifname { ${bridgeSet} } ether type arp accept
        iifname { ${bridgeSet} } ip daddr { ${gatewayIPSet} } accept
        iifname { ${bridgeSet} } counter drop
      '';
    };

    # ================ Network Optimizations ================
    systemd.network.wait-online = {
      timeout = 30; # Reduce from 120s to 30s
      anyInterface = true; # Don't wait for all interfaces
      ignoredInterfaces = [ "wg0" ]; # Ignore WireGuard
    };

    systemd.services.systemd-udev-settle.enable = false;
  };
}
