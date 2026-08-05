{
  config,
  lib,
  inputs,
  ...
}:
let
  cfg = config.custom.services.cloudflare-dyndns;
in
{
  imports = lib.flatten [
    (map lib.custom.relativeToRoot [ "modules/services/cloudflare-cnames.nix" ])
  ];

  options.custom.services.cloudflare-dyndns = {
    enable = lib.mkEnableOption "Cloudflare Dynamic DNS";
    ipv4 = lib.mkOption {
      type = lib.types.bool;
      description = "Update IPv4 A record";
    };
    ipv6 = lib.mkOption {
      type = lib.types.bool;
      description = "Update IPv6 AAAA record";
    };
  };

  config = lib.mkIf cfg.enable {
    # Cloudflare API credentials
    sops.secrets."cloudflare/api-token" = {
      sopsFile = "${builtins.toString inputs.nix-secrets}/sops/${config.hostSpec.hostName}.yaml";
      owner = "root";
      group = "root";
      mode = "0400";
    };

    services.cloudflare-dyndns = {
      enable = true;
      domains = [ config.hostSpec.domain ];
      apiTokenFile = config.sops.secrets."cloudflare/api-token".path;
      inherit (cfg) ipv4 ipv6;
    };

    # Also include cloudflare-cnames which was previously tied to this
    services.cloudflare-cnames = {
      enable = lib.mkDefault true;
      apiTokenFile = config.sops.secrets."cloudflare/api-token".path;
      domain = config.hostSpec.domain;
      records = [
        {
          name = "*";
          target = "@";
        }
        {
          name = "www";
          target = "@";
        }
      ];
    };
  };
}
