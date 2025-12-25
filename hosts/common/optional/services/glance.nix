# Glance - Dashboard/home page service
{ pkgs, ... }:
{
  services.glance = {
    enable = true;
    openFirewall = true;
    settings = {
      server = {
        host = "0.0.0.0";
        port = 5533;
      };
      theme = {
        # Kanagawa-ish theme
        background-color = "240 13 14";
        primary-color = "39 66 71";
        negative-color = "358 100 68";
        contrast-multiplier = 1.5;
      };
      pages = [
        {
          name = "Home";
          # hide-desktop-navigation = true;
          columns = [
            {
              size = "small";
              widgets = [
                {
                  type = "weather";
                  location = "London, United Kingdom";
                  units = "metric";
                  "hour-format" = "12h";
                  # hide-location = true;
                }
                {
                  type = "calendar";
                  "first-day-of-week" = "monday";
                }
              ];
            }
            {
              size = "full";
              widgets = [
                {
                  type = "group";
                  widgets = [
                    {
                      type = "reddit";
                      subreddit = "selfhosted";
                      "show-thumbnails" = true;
                      "collapse-after" = -1;
                    }
                  ];
                }
              ];
            }
            {
              size = "small";
              widgets = [

                {
                  type = "releases";
                  cache = "1d";
                  # token = "...";
                  repositories = [
                    "glanceapp/glance"
                    "immich-app/immich"
                    "jellyfin/jellyfin"
                  ];
                }
              ];
            }
          ];
        }
      ];
    };
  };
}
