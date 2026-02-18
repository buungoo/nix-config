# NixOS-specific option interface modules
# Imported globally so all hosts can set these options;
# implementation modules (haproxy.nix, kanidm.nix) consume them.
{ ... }:
{
  imports = [
    ./reverse-proxy.nix
    ./kanidm-oauth.nix
    ./jellyfin.nix
  ];
}
