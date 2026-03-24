{ config, ... }:

let
  autheliaUrl = "https://auth.justaslime.dev/";

  trustedProxyCidrs = [
    "127.0.0.1/32"
    "::1/128"
    "192.168.1.0/24"
  ];
in
{
  services.traefik = {
    enable = true;

    staticConfigOptions = {
      global = {
        checkNewVersion = false;
        sendAnonymousUsage = false;
      };

      log.level = "INFO";

      entryPoints = {
        web = {
          address = ":80";

          forwardedHeaders.trustedIPs = trustedProxyCidrs;

          http.redirections.entryPoint = {
            to = "websecure";
            scheme = "https";
            permanent = true;
          };
        };

        websecure = {
          address = ":443";

          forwardedHeaders.trustedIPs = trustedProxyCidrs;
        };
      };

      providers.file.watch = true;
    };

    dynamicConfigOptions = {
      tls.certificates = [
        {
          certFile = config.sops.secrets."cloudflare-origin-ca-cert".path;
          keyFile = config.sops.secrets."cloudflare-origin-ca-key".path;
        }
      ];

      http.middlewares.authelia.forwardAuth = {
        address = "http://127.0.0.1:9091/api/verify?rd=https%3A%2F%2Fauth.justaslime.dev%2F";
        trustForwardHeader = true;
        authResponseHeaders = [
          "Remote-User"
          "Remote-Groups"
          "Remote-Email"
          "Remote-Name"
        ];
      };

      http.routers = {
        authelia = {
          rule = "Host(`auth.justaslime.dev`)";
          entryPoints = [ "websecure" ];

          service = "authelia";
          tls = true;
        };

        forgejo-git = {
          rule = "Host(`code.justaslime.dev`) && (PathRegexp(`^/.+/.+\\.git/info/refs$`) || PathRegexp(`^/.+/.+\\.git/git-upload-pack$`) || PathRegexp(`^/.+/.+\\.git/git-receive-pack$`) || PathRegexp(`^/.+/.+\\.git/info/lfs/.*$`))";
          entryPoints = [ "websecure" ];
          priority = 100;

          service = "forgejo";
          tls = true;
        };

        forgejo = {
          rule = "Host(`code.justaslime.dev`)";
          entryPoints = [ "websecure" ];

          service = "forgejo";
          tls = true;
        };

        woodpecker-hook = {
          rule = "Host(`ci.justaslime.dev`) && Path(`/api/hook`)";
          entryPoints = [ "websecure" ];
          priority = 100;

          service = "woodpecker";
          tls = true;
        };

        woodpecker = {
          rule = "Host(`ci.justaslime.dev`)";
          entryPoints = [ "websecure" ];
          middlewares = [ "authelia@file" ];

          service = "woodpecker";
          tls = true;
        };
      };

      http.services = {
        authelia.loadBalancer.servers = [ { url = "http://127.0.0.1:9091"; } ];
        forgejo.loadBalancer.servers = [ { url = "http://127.0.0.1:3000"; } ];
        woodpecker.loadBalancer.servers = [ { url = "http://127.0.0.1:8000"; } ];
      };
    };
  };
}
