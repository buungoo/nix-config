# Cloudflare Dynamic DNS - keeps A/AAAA records updated with current public IP
{ config, lib, inputs, ... }:
{
  imports = lib.flatten [
    (map lib.custom.relativeToRoot [ "modules/services/cloudflare-cnames.nix" ])
  ];

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
