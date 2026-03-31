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
    "show-thumbnails" = true;
    "collapse-after-rows" = 9;
  };

  mkRedditGroup = subreddits: {
    type = "group";
    widgets = builtins.map mkRedditWidget subreddits;
  };

  dynacatConfig = (pkgs.formats.yaml { }).generate "dynacat.yml" {
    server = {
      host = "127.0.0.1";
      port = 8082;
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
        name = "Apps & Bookmarks";
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
              {
                type = "monitor";
                title = "Applications";
                "update-interval" = "45s";
                sites = [
                  {
                    title = "Authelia";
                    url = "https://auth.justaslime.dev";
                    icon = "mdi:shield-account";
                    description = "Identity and SSO gateway";
                    "check-url" = "http://127.0.0.1:9091";
                  }
                  {
                    title = "Forgejo";
                    url = "https://code.justaslime.dev";
                    icon = "si:forgejo";
                    description = "Git hosting, packages, and project history";
                    "check-url" = "http://127.0.0.1:3000";
                  }
                  {
                    title = "Woodpecker";
                    url = "https://ci.justaslime.dev";
                    icon = "mdi:pipe";
                    description = "CI pipelines and hooks";
                    "check-url" = "http://127.0.0.1:8000";
                  }
                ];
              }
            ];
          }
          {
            size = "full";
            widgets = [
              {
                type = "bookmarks";
                groups = [
                  {
                    title = "Homolab";
                    links = [
                      {
                        title = "Server Home";
                        url = "https://home.justaslime.dev";
                        description = "Dynacat dashboard entrypoint";
                        icon = "mdi:view-dashboard";
                      }
                      {
                        title = "NixOS Search";
                        url = "https://search.nixos.org/packages";
                        description = "Find packages and options";
                        icon = "si:nixos";
                      }
                      {
                        title = "Dynacat Docs";
                        url = "https://github.com/Panonim/dynacat/blob/main/docs/docs/configuration.md";
                        description = "Dynacat widget and config reference";
                        icon = "si:github";
                      }
                    ];
                  }
                  {
                    title = "Media Links";
                    links = [
                      {
                        title = "YouTube";
                        url = "https://www.youtube.com";
                        description = "Video subscriptions and watchlist";
                        icon = "si:youtube";
                      }
                      {
                        title = "Weather";
                        url = "https://wttr.in";
                        description = "Quick forecast outside the status bar";
                        icon = "mdi:weather-partly-cloudy";
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
        columns = [
          {
            size = "full";
            widgets = [
              {
                type = "split-column";
                "max-columns" = 3;
                widgets = [
                  (mkRedditGroup [
                    "opencodeCLI"
                    "LocalLLaMA"
                    "ClaudeAI"
                  ])
                  (mkRedditGroup [
                    "selfhosted"
                    "browser"
                    "theprimeagen"
                    "rust"
                    "zig"
                    "neovim"
                  ])
                  (mkRedditGroup [
                    "KeqingMains"
                    "C_AT"
                    "BlueArchive"
                  ])
                ];
              }
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
                type = "monitor";
                title = "Core Services";
                "update-interval" = "45s";
                sites = [
                  {
                    title = "Traefik";
                    url = "https://home.justaslime.dev";
                    icon = "si:traefikproxy";
                    description = "Edge router for homolab services";
                    "check-url" = "http://127.0.0.1:80";
                  }
                  {
                    title = "Docker API";
                    url = "http://127.0.0.1:2375/version";
                    icon = "si:docker";
                    description = "Container runtime API endpoint";
                  }
                  {
                    title = "Cloudflare DDNS";
                    url = "https://justaslime.dev";
                    icon = "si:cloudflare";
                    description = "DNS update pipeline";
                    "check-url" = "https://1.1.1.1";
                  }
                ];
              }
              {
                type = "docker-containers";
                title = "Containers";
                "sock-path" = "/var/run/docker.sock";
                "update-interval" = "45s";
                "format-container-names" = true;
              }
            ];
          }
          {
            size = "full";
            widgets = [
              {
                type = "server-stats";
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
                type = "custom-api";
                title = "Docker Engine";
                cache = "5m";
                url = "http://127.0.0.1:2375/version";
                template = ''
                  <div class="flex justify-between text-center">
                    <div>
                      <div class="color-highlight size-h4">{{ .JSON.String "Version" }}</div>
                      <div class="size-h6">ENGINE</div>
                    </div>
                    <div>
                      <div class="color-highlight size-h4">{{ .JSON.String "ApiVersion" }}</div>
                      <div class="size-h6">API</div>
                    </div>
                  </div>
                '';
              }
              {
                type = "custom-api";
                title = "Ollama";
                cache = "2m";
                url = "http://192.168.1.127:11434/api/tags";
                template = ''
                  <div class="flex justify-between text-center">
                    <div>
                      <div class="color-highlight size-h4">{{ .JSON.String "models.0.name" }}</div>
                      <div class="size-h6">TOP MODEL</div>
                    </div>
                  </div>
                '';
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
