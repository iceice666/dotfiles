{ ... }:

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
      ];
    };

    widgets = [
      {
        resources = {
          cpu = true;
          memory = true;
          disk = "/";
        };
      }
      {
        search = {
          provider = "duckduckgo";
          target = "_blank";
        };
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
    ];
  };
}
