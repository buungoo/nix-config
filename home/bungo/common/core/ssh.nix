{
  pkgs,
  inputs,
  ...
}:
let
  nas0Config = inputs.nix-secrets.nas0;
  nas0WireguardIP = nas0Config.networking.wireguardIP;
  nas0LanIP = nas0Config.networking.localIP;

  nas1Config = inputs.nix-secrets.nas1;
  nas1WireguardIP = nas1Config.networking.wireguardIP;
  nas1LanIP = nas1Config.networking.localIP;
in
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    matchBlocks = {
      "git" = {
        host = "gitlab.com github.com";
        user = "git";
        identitiesOnly = true;
        identityFile = "~/.ssh/id_ed25519";
      };

      "nas0" = {
        user = "bungo";
        identityFile = "~/.ssh/id_ed25519";
        # Try Wireguard IP first, fall back to LAN IP
        # nc -z tests connectivity with 1 second timeout
        proxyCommand = "sh -c '${pkgs.netcat}/bin/nc -z -w1 ${nas0WireguardIP} 22 2>/dev/null && exec ${pkgs.netcat}/bin/nc ${nas0WireguardIP} 22 || exec ${pkgs.netcat}/bin/nc ${nas0LanIP} 22'";
      };

      "nas1" = {
        user = "bungo";
        identityFile = "~/.ssh/id_ed25519";
        proxyCommand = "sh -c '${pkgs.netcat}/bin/nc -z -w1 ${nas1WireguardIP} 22 2>/dev/null && exec ${pkgs.netcat}/bin/nc ${nas1WireguardIP} 22 || exec ${pkgs.netcat}/bin/nc ${nas1LanIP} 22'";
      };
    };
  };
}
