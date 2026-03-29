{ config, ... }:

{
  services.homepage-dashboard = {
    enable = true;
    listenPort = 8082;
    allowedHosts = "localhost:8082,127.0.0.1:8082,home.justaslime.dev";
    environmentFile = config.sops.templates."homepage-dashboard.env".path;

    settings = {
      title = "homolab";
      description = "Tabbed control center for apps, media, and system health";

      headerStyle = "boxedWidgets";
      fullWidth = true;
      useEqualHeights = true;
      statusStyle = "dot";

      quicklaunch = {
        searchDescriptions = true;
        hideInternetSearch = true;
        showSearchSuggestions = true;
        provider = "duckduckgo";
        mobileButtonPosition = "bottom-right";
      };

      layout = [
        {
          Apps = {
            style = "row";
            columns = 3;
            tab = "App & Bookmarks";
          };
        }
        {
          Bookmarks = {
            style = "row";
            columns = 3;
            tab = "App & Bookmarks";
          };
        }
        {
          Media = {
            style = "row";
            columns = 2;
            tab = "Media";
          };
        }
        {
          "Media Links" = {
            style = "row";
            columns = 3;
            tab = "Media";
          };
        }
        {
          System = {
            style = "row";
            columns = 3;
            tab = "System";
          };
        }
        {
          "System Links" = {
            style = "row";
            columns = 3;
            tab = "System";
          };
        }
      ];
    };

    widgets = [
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
          label = "homolab";
          cpu = true;
          memory = true;
          uptime = true;
          disk = [
            "/"
            "/mnt/storage"
          ];
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
        Bookmarks = [
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
            "Server Home" = [
              {
                abbr = "HM";
                href = "https://home.justaslime.dev";
                description = "Dashboard entrypoint for homolab";
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
        "Media Links" = [
          {
            YouTube = [
              {
                abbr = "YT";
                href = "https://www.youtube.com";
                description = "Video subscriptions and watchlist";
              }
            ];
          }
          {
            Weather = [
              {
                abbr = "WX";
                href = "https://wttr.in";
                description = "Quick forecast outside the status bar";
              }
            ];
          }
        ];
      }
      {
        "System Links" = [
          {
            Router = [
              {
                abbr = "GW";
                href = "http://192.168.1.1";
                description = "LAN gateway and network controls";
              }
            ];
          }
          {
            "Ollama API" = [
              {
                abbr = "AI";
                href = "http://192.168.1.127:11434";
                description = "Direct access to the local model endpoint";
              }
            ];
          }
          {
            "Docker Engine" = [
              {
                abbr = "DK";
                href = "http://127.0.0.1:2375/version";
                description = "Raw Docker API version endpoint";
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
              icon = "mdi-shield-account";
              href = "https://auth.justaslime.dev";
              description = "Identity and SSO gateway";
              siteMonitor = "http://127.0.0.1:9091";
              ping = "127.0.0.1";
            };
          }
          {
            Forgejo = {
              icon = "si-forgejo";
              href = "https://code.justaslime.dev";
              description = "Git hosting, packages, and project history";
              siteMonitor = "http://127.0.0.1:3000";
              ping = "127.0.0.1";
            };
          }
          {
            Woodpecker = {
              icon = "mdi-pipe";
              href = "https://ci.justaslime.dev";
              description = "CI pipelines, hooks, and container builds";
              siteMonitor = "http://127.0.0.1:8000";
              ping = "127.0.0.1";
            };
          }
          {
            Homepage = {
              icon = "mdi-view-dashboard";
              href = "https://home.justaslime.dev";
              description = "This dashboard with tabs, search, and service health";
              siteMonitor = "http://127.0.0.1:8082";
              ping = "127.0.0.1";
            };
          }
        ];
      }
      {
        System = [
          {
            Traefik = {
              icon = "si-traefikproxy";
              description = "Edge router for homolab services";
              ping = "127.0.0.1";
            };
          }
          {
            Ollama = {
              icon = "mdi-robot-outline";
              href = "http://192.168.1.127:11434";
              description = "Local LLM runtime on the homolab host";
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
              icon = "si-postgresql";
              description = "Socket-only database for Authelia and Forgejo";
              ping = "127.0.0.1";
            };
          }
          {
            Valkey = {
              icon = "si-valkey";
              description = "Local cache and queue backend";
              ping = "127.0.0.1";
            };
          }
          {
            Docker = {
              icon = "si-docker";
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
              icon = "mdi-console-network";
              description = "LAN-only SSH on port 2222";
              ping = "192.168.1.127";
            };
          }
          {
            "Cloudflare DDNS" = {
              icon = "si-cloudflare";
              description = "Updates justaslime.dev and proxy.justaslime.dev";
              ping = "1.1.1.1";
            };
          }
          {
            "Cloudflare Tunnel" = {
              icon = "si-cloudflare";
              description = "Outbound tunnel for Cloudflare edge connectivity";
              ping = "1.1.1.1";
            };
          }
          {
            "Cloudflare IP Refresh" = {
              icon = "si-cloudflare";
              description = "Daily allowlist refresh for HTTP and HTTPS";
              ping = "1.1.1.1";
            };
          }
        ];
      }
      {
        Media = [
          {
            FreshRSS = {
              icon = "mdi-rss-box";
              href = "https://rss.justaslime.dev";
              description = "RSS inbox with your migrated YouTube subscriptions";
              siteMonitor = "http://127.0.0.1:8083";
              ping = "127.0.0.1";
              widget = {
                type = "freshrss";
                url = "http://127.0.0.1:8083";
                username = "iceice666";
                password = "{{HOMEPAGE_VAR_FRESHRSS_API_PASSWORD}}";
                unread = true;
                subscriptions = true;
              };
            };
          }
        ];
      }
    ];
  };
}
