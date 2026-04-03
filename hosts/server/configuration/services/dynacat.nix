{ pkgs, ... }:

let
  mkVideosWidget = title: channels: {
    type = "videos";
    inherit title channels;
    style = "grid-cards";
    "include-shorts" = false;
    "collapse-after-rows" = 3;
  };

  mkRedditWidget = subreddit: {
    type = "reddit";
    inherit subreddit;
    style = "vertical-list";
    "show-thumbnails" = true;
    limit = 50;
    "collapse-after" = -1;
  };

  mkRedditGroup = subreddits: {
    type = "group";
    widgets = builtins.map mkRedditWidget subreddits;
  };

  mkMonitorSite =
    {
      title,
      url,
      icon,
      description,
      checkUrl ? null,
    }:
    {
      inherit
        title
        url
        icon
        description
        ;
    }
    // (if checkUrl != null then { "check-url" = checkUrl; } else { });

  autheliaSite = mkMonitorSite {
    title = "Authelia";
    url = "https://auth.justaslime.dev";
    icon = "sh:authelia";
    description = "Identity and SSO";
    checkUrl = "http://127.0.0.1:9091";
  };

  forgejoSite = mkMonitorSite {
    title = "Forgejo";
    url = "https://code.justaslime.dev";
    icon = "sh:forgejo";
    description = "Git hosting";
    checkUrl = "http://127.0.0.1:17303";
  };

  woodpeckerSite = mkMonitorSite {
    title = "Woodpecker";
    url = "https://ci.justaslime.dev";
    icon = "https://woodpecker-ci.org/img/logo.svg";
    description = "CI pipelines";
    checkUrl = "http://127.0.0.1:17800";
  };

  traefikSite = mkMonitorSite {
    title = "Traefik";
    url = "https://home.justaslime.dev";
    icon = "sh:traefik";
    description = "Ingress and TLS";
    checkUrl = "http://127.0.0.1:18081/ping";
  };

  dockerApiSite = mkMonitorSite {
    title = "Docker API";
    url = "http://127.0.0.1:2375/version";
    icon = "sh:docker";
    description = "Container control plane";
    checkUrl = "http://127.0.0.1:2375/version";
  };

  ollamaSite = mkMonitorSite {
    title = "Ollama";
    url = "http://192.168.1.127:11434/api/tags";
    icon = "sh:ollama";
    description = "LLM inference API";
    checkUrl = "http://192.168.1.127:11434/api/tags";
  };

  cloudflareDdnsSite = mkMonitorSite {
    title = "Cloudflare DDNS";
    url = "https://justaslime.dev";
    icon = "sh:cloudflare";
    description = "Public DNS reachability";
    checkUrl = "https://1.1.1.1";
  };

  cloudflaredTunnelSite = mkMonitorSite {
    title = "Cloudflared Tunnel";
    url = "https://one.dash.cloudflare.com";
    icon = "sh:cloudflare";
    description = "Cloudflare tunnel agent";
    checkUrl = "http://127.0.0.1:49312/ready";
  };

  myServiceSites = [
    forgejoSite
    woodpeckerSite
    cloudflaredTunnelSite
  ];
  publicServiceSites = [
    autheliaSite
    forgejoSite
    woodpeckerSite
  ];
  infrastructureSites = [
    traefikSite
    dockerApiSite
    cloudflareDdnsSite
    cloudflaredTunnelSite
  ];
  aiServiceSites = [ ollamaSite ];
  incidentSites = publicServiceSites ++ infrastructureSites ++ aiServiceSites;

  dynacatConfig = (pkgs.formats.yaml { }).generate "dynacat.yml" {
    server = {
      host = "127.0.0.1";
      port = 18082;
      proxied = true;
    };

    branding = {
      "app-name" = "homolab";
      "hide-footer" = true;
      "logo-text" = "H";
    };

    theme = {
      "background-color" = "294 9 22";
      "primary-color" = "30 19 75";
      "positive-color" = "150 4 61";
      "negative-color" = "9 24 54";
      "contrast-multiplier" = 1.25;
    };

    pages = [
      {
        name = "Portal";
        columns = [
          {
            size = "small";
            widgets = [
              {
                type = "clock";
                "hour-format" = "24h";
              }
              {
                type = "weather";
                units = "metric";
                "hour-format" = "24h";
                location = "Tainan, Taiwan";
              }
            ];
          }
          {
            size = "full";
            widgets = [
              {
                type = "split-column";
                "max-columns" = 2;
                widgets = [
                  {
                    type = "monitor";
                    title = "My Services";
                    "update-interval" = "30s";
                    sites = myServiceSites;
                  }
                  {
                    type = "bookmarks";
                    groups = [
                      {
                        title = "External";
                        links = [
                          {
                            title = "YouTube";
                            url = "https://www.youtube.com";
                            description = "Video platform";
                            icon = "sh:youtube";
                          }
                          {
                            title = "Bilibili";
                            url = "https://www.bilibili.com";
                            description = "Bilibili homepage";
                            icon = "https://api.iconify.design/simple-icons:bilibili.svg?color=%2300A1D6";
                          }
                          {
                            title = "Twitter";
                            url = "https://twitter.com";
                            description = "X social feed";
                            icon = "https://api.iconify.design/mdi:twitter.svg?color=%231DA1F2";
                          }
                          {
                            title = "Reddit";
                            url = "https://www.reddit.com";
                            description = "Community feed";
                            icon = "sh:reddit";
                          }
                          {
                            title = "GitHub";
                            url = "https://github.com";
                            description = "Code hosting";
                            icon = "sh:github";
                          }
                          {
                            title = "Cloudflare Dashboard";
                            url = "https://dash.cloudflare.com";
                            icon = "sh:cloudflare";
                            description = "DNS and zone management";
                          }
                          {
                            title = "Cloudflare One Dashboard";
                            url = "https://dash.cloudflare.com/one";
                            icon = "sh:cloudflare";
                            description = "Zero Trust portal";
                          }
                        ];
                      }
                    ];
                  }
                ];
              }
            ];
          }
        ];
      }
      {
        name = "YouTube";
        columns = [
          {
            size = "full";
            widgets = [
              {
                type = "split-column";
                "max-columns" = 2;
                widgets = [
                  (mkVideosWidget "Music" [
                    "UCam3IAA-nyfxRL8_wDQ35VA"
                    "UCah4_WVjmr8XA7i5aigwV-Q"
                  ])
                  (mkVideosWidget "Tech" [
                    "UCsBjURrPoezykLs9EqgamOA"
                    "UC6biysICWOJ-C3P4Tyeggzg"
                    "UCUyeluBRhGPCW4rPe_UvBZQ"
                    "UCbRP3c757lWg9M-U7TyEkXA"
                    "UCEbYhDd6c6vngsF5PQpFVWg"
                    "UCrqM0Ym_NbK1fqeQG2VIohg"
                  ])
                ];
              }
            ];
          }
        ];
      }
      {
        name = "Reddit";
        width = "wide";
        columns = [
          {
            size = "full";
            widgets = [
              (mkRedditGroup [
                "opencodeCLI"
                "LocalLLaMA"
                "ClaudeAI"
                "selfhosted"
                "browser"
                "theprimeagen"
                "rust"
                "zig"
                "neovim"
                "KeqingMains"
                "C_AT"
                "BlueArchive"
              ])
            ];
          }
        ];
      }
      {
        name = "System";
        columns = [
          {
            size = "small";
            widgets = [
              {
                type = "server-stats";
                "hide-swap" = true;
                "hide-mountpoints-by-default" = true;
                servers = [
                  {
                    type = "local";
                    name = "homolab";
                    mountpoints = {
                      "/".name = "RootFS";
                      "/mnt/storage".name = "Storage";
                    };
                  }
                ];
              }

              {
                type = "monitor";
                title = "Incidents";
                style = "compact";
                "show-failing-only" = true;
                "update-interval" = "30s";
                sites = incidentSites;
              }
              {
                type = "docker-containers";
                title = "Containers";
                "sock-path" = "/var/run/docker.sock";
                "update-interval" = "30s";
                "running-only" = true;
                "format-container-names" = true;
              }
            ];
          }
          {
            size = "full";
            widgets = [
              {
                type = "split-column";
                "max-columns" = 3;
                widgets = [
                  {
                    type = "monitor";
                    title = "Public Services";
                    "update-interval" = "30s";
                    sites = publicServiceSites;
                  }
                  {
                    type = "monitor";
                    title = "Infrastructure";
                    "update-interval" = "30s";
                    sites = infrastructureSites;
                  }
                  {
                    type = "monitor";
                    title = "AI Services";
                    "update-interval" = "30s";
                    sites = aiServiceSites;
                  }
                ];
              }

            ];
          }
        ];
      }
    ];
  };
in
{
  virtualisation.oci-containers = {
    backend = "docker";

    containers.dynacat = {
      serviceName = "dynacat";
      image = "panonim/dynacat:2.0.1";
      extraOptions = [ "--network=host" ];
      environment = {
        ENABLE_DYNAMIC_UPDATE = "true";
      };
      volumes = [
        "${dynacatConfig}:/app/config/dynacat.yml:ro"
        "/var/run/docker.sock:/var/run/docker.sock"
      ];
    };
  };
}
