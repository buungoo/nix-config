# NixOS-specific option interface modules
# Imported globally so all hosts can set these options;
# implementation modules consume them.
{ ... }:
{
  imports = [
    ./reverse-proxy.nix
    ./kanidm-oauth.nix
    ./jellyfin.nix
    ./immich.nix
    ./sonarr.nix
    ./qbittorrent.nix
    ./qbit-manage.nix
    ./prowlarr.nix
    ./radarr.nix
    ./bazarr.nix
    ./jellyseerr.nix
    ./samba-client.nix
    ./netbird.nix
    ./cross-seed.nix
    ./cloudflare-dyndns.nix
    ./planka.nix
    ./tandoor.nix
  ];
}
