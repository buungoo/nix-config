# Cloudflare Dynamic DNS - keeps A/AAAA records updated with current public IP
{ config, ... }:
{
  services.cloudflare-dyndns = {
    enable = true;
    domains = [ config.hostSpec.domain ];
    apiTokenFile = config.sops.secrets."cloudflare/api-token".path;
    ipv4 = true;
    ipv6 = true;
  };
}
