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
              description = "Whether the reverse proxy routes WAN traffic to this service";
            };
            mTLS = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Require mTLS (step-ca client certificate) for WAN access. Only applies when proxyWan = true.";
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
            backendH2 = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Use HTTP/2 for backend connections (required for gRPC services)";
            };
            extraBackends = lib.mkOption {
              type = lib.types.attrsOf (
                lib.types.submodule {
                  options = {
                    pathPrefix = lib.mkOption {
                      type = lib.types.str;
                      description = "URL path prefix to match (e.g. /signalexchange.SignalExchange/)";
                    };
                    backendHost = lib.mkOption {
                      type = lib.types.str;
                      description = "Backend host IP address for this path";
                    };
                    backendPort = lib.mkOption {
                      type = lib.types.port;
                      description = "Backend port for this path";
                    };
                  };
                }
              );
              default = { };
              description = "Path-based backend overrides. Traffic matching a pathPrefix routes to its backend instead of the default.";
            };
          };
        }
      )
    );
    default = { };
  };
}
