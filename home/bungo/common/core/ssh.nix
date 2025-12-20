{
  pkgs,
  inputs,
  ...
}:
let
  nas0Config = inputs.nix-secrets.nas0;
  wireguardIP = nas0Config.networking.wireguardIP;
  lanIP = nas0Config.networking.localIP;
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
        proxyCommand = "sh -c '${pkgs.netcat}/bin/nc -z -w1 ${wireguardIP} 22 2>/dev/null && exec ${pkgs.netcat}/bin/nc ${wireguardIP} 22 || exec ${pkgs.netcat}/bin/nc ${lanIP} 22'";
      };
    };
  };
}
