# Interface module: declares custom.reverseProxy.virtualHosts
# Consumed by haproxy.nix (proxy routing + ACME certs) and unbound.nix (split-horizon DNS)
#
# Services declare their own virtual hosts:
#   custom.reverseProxy.virtualHosts.myservice = {
#     domain = "myservice.example.com";
#     backendHost = "10.0.0.2";
#     backendPort = 8080;
#   };
#
# For ACME-cert-only hosts (no proxy routing), omit backendHost/backendPort:
#   custom.reverseProxy.virtualHosts.files = {
#     domain = "files.example.com";
#     public = false;
#   };
{ lib, ... }:
{
  options.custom.reverseProxy.virtualHosts = lib.mkOption {
    description = "Virtual host definitions for reverse proxy, ACME certificates, and DNS";
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, ... }:
        {
          options = {
            domain = lib.mkOption {
              type = lib.types.str;
              description = "Fully qualified domain name for ${name}";
            };
            proxyWan = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Whether the reverse proxy routes WAN traffic to this service using mTLS";
            };
            backendHost = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Backend host IP address. Null means ACME-only (no proxy routing).";
            };
            backendPort = lib.mkOption {
              type = lib.types.nullOr lib.types.port;
              default = null;
              description = "Backend port. Null means ACME-only (no proxy routing).";
            };
            backendSSL = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Whether the backend uses SSL";
            };
          };
        }
      )
    );
    default = { };
  };
}
