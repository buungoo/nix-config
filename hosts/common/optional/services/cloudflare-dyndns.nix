# Cloudflare Dynamic DNS - keeps A/AAAA records updated with current public IP
{ config, lib, ... }:
{
  imports = lib.flatten [
    (map lib.custom.relativeToRoot [ "modules/services/cloudflare-cnames.nix" ])
  ];

  services.cloudflare-dyndns = {
    enable = true;
    domains = [ config.hostSpec.domain ];
    apiTokenFile = config.sops.secrets."cloudflare/api-token".path;
    ipv4 = true;
    ipv6 = true;
  };

  services.cloudflare-cnames = {
    enable = true;
    apiTokenFile = config.sops.secrets."cloudflare/api-token".path;
    domain = config.hostSpec.domain;
    records = [
      { name = "*"; target = "@"; }
      { name = "www"; target = "@"; }
    ];
  };
}
