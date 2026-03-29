{ ... }:

let
  techYoutubeChannels = builtins.concatStringsSep "," [
    "UCbRP3c757lWg9M-U7TyEkXA"
    "UCEbYhDd6c6vngsF5PQpFVWg"
    "UCrqM0Ym_NbK1fqeQG2VIohg"
    "UCUyeluBRhGPCW4rPe_UvBZQ"
    "UC6biysICWOJ-C3P4Tyeggzg"
    "UCsBjURrPoezykLs9EqgamOA"
  ];
  musicYoutubeChannels = builtins.concatStringsSep "," [
    "UCam3IAA-nyfxRL8_wDQ35VA"
    "UCah4_WVjmr8XA7i5aigwV-Q"
  ];
  youtubeTechProxyUrl = "http://127.0.0.1:8095/videos?limit=8&channels=${techYoutubeChannels}";
  youtubeMusicProxyUrl = "http://127.0.0.1:8095/videos?limit=8&channels=${musicYoutubeChannels}";
in
{
  services.homepage-dashboard = {
    enable = true;
    listenPort = 8082;
    allowedHosts = "localhost:8082,127.0.0.1:8082,home.justaslime.dev";

    settings = {
      title = "homolab";
      description = "Service dashboard for JustaSlime";

      headerStyle = "boxedWidgets";

      layout = [
        {
          Apps = {
            style = "row";
            columns = 3;
          };
        }
        {
          Infrastructure = {
            style = "row";
            columns = 3;
          };
        }
        {
          Media = {
            style = "row";
            columns = 2;
          };
        }
      ];
    };

    widgets = [
      {
        greeting = {
          text_size = "xl";
          text = "Welcome back, JustaSlime";
        };
      }
      {
        datetime = {
          text_size = "xl";
          format = {
            dateStyle = "medium";
            timeStyle = "short";
            hourCycle = "h23";
          };
        };
      }
      {
        resources = {
          cpu = true;
          memory = true;
          disk = "/";
        };
      }
      {
        openmeteo = {
          label = "homolab";
          units = "metric";
          cache = 10;
        };
      }
      {
        search = {
          provider = "duckduckgo";
          target = "_blank";
        };
      }
    ];

    bookmarks = [
      {
        Dev = [
          {
            "NixOS Search" = [
              {
                abbr = "NX";
                href = "https://search.nixos.org/packages";
                description = "Find packages and options";
              }
            ];
          }
          {
            "Homepage Docs" = [
              {
                abbr = "HP";
                href = "https://gethomepage.dev";
                description = "Widget and config reference";
              }
            ];
          }
        ];
      }
      {
        Media = [
          {
            YouTube = [
              {
                abbr = "YT";
                href = "https://www.youtube.com";
                description = "Video subscriptions and watchlist";
              }
            ];
          }
        ];
      }
    ];

    services = [
      {
        Apps = [
          {
            Authelia = {
              href = "https://auth.justaslime.dev";
              description = "Identity and SSO gateway";
              siteMonitor = "https://auth.justaslime.dev";
              ping = "127.0.0.1";
            };
          }
          {
            Forgejo = {
              href = "https://code.justaslime.dev";
              description = "Git hosting and package registry";
              siteMonitor = "https://code.justaslime.dev";
              ping = "127.0.0.1";
            };
          }
          {
            Woodpecker = {
              href = "https://ci.justaslime.dev";
              description = "CI pipelines and build agents";
              siteMonitor = "https://ci.justaslime.dev";
              ping = "127.0.0.1";
            };
          }
        ];
      }
      {
        Infrastructure = [
          {
            Traefik = {
              description = "Edge router for homolab services";
              ping = "127.0.0.1";
            };
          }
          {
            Ollama = {
              href = "http://192.168.1.127:11434";
              description = "Local LLM API on the homolab host";
              ping = "192.168.1.127";
              widget = {
                type = "customapi";
                url = "http://192.168.1.127:11434/api/tags";
                refreshInterval = 120000;
                mappings = [
                  {
                    field = "models";
                    label = "Models";
                    format = "size";
                  }
                  {
                    field = "models.0.name";
                    label = "Top model";
                  }
                ];
              };
            };
          }
          {
            PostgreSQL = {
              description = "Socket-only database for Authelia and Forgejo";
              ping = "127.0.0.1";
            };
          }
          {
            Valkey = {
              description = "Local cache and queue backend";
              ping = "127.0.0.1";
            };
          }
          {
            Docker = {
              description = "Container runtime for local workloads";
              ping = "127.0.0.1";
              widget = {
                type = "customapi";
                url = "http://127.0.0.1:2375/version";
                refreshInterval = 300000;
                mappings = [
                  {
                    field = "Version";
                    label = "Engine";
                  }
                  {
                    field = "ApiVersion";
                    label = "API";
                  }
                ];
              };
            };
          }
          {
            OpenSSH = {
              description = "LAN-only SSH on port 2222";
              ping = "192.168.1.127";
            };
          }
          {
            "Cloudflare DDNS" = {
              description = "Updates justaslime.dev and proxy.justaslime.dev";
              ping = "1.1.1.1";
            };
          }
          {
            "Cloudflare Tunnel" = {
              description = "Outbound tunnel for Cloudflare edge connectivity";
              ping = "1.1.1.1";
            };
          }
          {
            "Cloudflare IP Refresh" = {
              description = "Daily allowlist refresh for HTTP and HTTPS";
              ping = "1.1.1.1";
            };
          }
        ];
      }
      {
        Media = [
          {
            "YouTube Tech" = {
              href = "https://www.youtube.com";
              description = "Latest uploads from your tech channels";
              ping = "127.0.0.1";
              widget = {
                type = "customapi";
                url = youtubeTechProxyUrl;
                refreshInterval = 300000;
                display = "dynamic-list";
                mappings = {
                  items = "videos";
                  name = "displayTitle";
                  label = "published";
                  format = "relativeDate";
                  target = "{url}";
                  limit = 8;
                };
              };
            };
          }
          {
            "YouTube Music" = {
              href = "https://www.youtube.com";
              description = "Latest uploads from your music channels";
              ping = "127.0.0.1";
              widget = {
                type = "customapi";
                url = youtubeMusicProxyUrl;
                refreshInterval = 300000;
                display = "dynamic-list";
                mappings = {
                  items = "videos";
                  name = "displayTitle";
                  label = "published";
                  format = "relativeDate";
                  target = "{url}";
                  limit = 8;
                };
              };
            };
          }
        ];
      }
    ];
  };
}
