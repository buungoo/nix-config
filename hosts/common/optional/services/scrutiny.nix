# Scrutiny - Disk health monitoring service
{ pkgs, ... }:
{
  services.scrutiny = {
    enable = true;
    openFirewall = true;
    settings.web.listen = {
      host = "0.0.0.0";
      port = 5532;
    };
  };
}
