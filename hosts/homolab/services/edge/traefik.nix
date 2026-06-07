{
  config,
  homolab,
  pkgs,
  unstablePkgs,
  ...
}:

let
  trustedProxyCidrs = [
    "127.0.0.1/32"
    "::1/128"
  ];

  testWildcardDomain = "test.${homolab.domains.root}";

  # Keep internal routes portless while only matching LAN, tailnet, or local callers.
  privateClientRule = "(ClientIP(`127.0.0.1/32`) || ClientIP(`::1/128`) || ClientIP(`${homolab.network.lan.cidr}`) || ClientIP(`100.64.0.0/10`) || ClientIP(`fd7a:115c:a1e0::/48`))";

  mkHostRule = host: "Host(`${host}`)";
  mkHostPathRule = host: pathRule: "${mkHostRule host} && ${pathRule}";
  mkPrivateHostRule = host: "${mkHostRule host} && ${privateClientRule}";
  mkPrivateHostPathRule = host: pathRule: "${mkPrivateHostRule host} && ${pathRule}";
  devPortClientRule = "(ClientIP(`127.0.0.1/32`) || ClientIP(`::1/128`) || ClientIP(`${homolab.network.lan.cidr}`) || ClientIP(`100.64.0.0/10`) || ClientIP(`fd7a:115c:a1e0::/48`))";
  devPortRule = "HostRegexp(`^3[0-9]{3}\\.test\\.${
    builtins.replaceStrings [ "." ] [ "\\." ] homolab.domains.root
  }$`) && ${devPortClientRule}";
  devPortTls = {
    certResolver = "letsencrypt";
    domains = [
      {
        main = testWildcardDomain;
        sans = [ "*.${testWildcardDomain}" ];
      }
    ];
  };

  npuHostRegex = builtins.replaceStrings [ "." ] [ "\\." ] homolab.domains.npu;
  technitiumHost = homolab.domains.dns;
in
{
  services.traefik = {
    enable = true;
    package = unstablePkgs.traefik;

    staticConfigOptions = {
      global = {
        checkNewVersion = false;
        sendAnonymousUsage = false;
      };

      certificatesResolvers.letsencrypt.acme = {
        email = homolab.contact.adminEmail;
        storage = "/var/lib/traefik/acme.json";
        dnsChallenge = {
          provider = "cloudflare";
          resolvers = [
            "1.1.1.1:53"
            "1.0.0.1:53"
          ];
        };
      };

      api.dashboard = true;

      log = {
        level = "INFO";
        format = "json";
      };

      accessLog = {
        format = "json";
        bufferingSize = 100;
        filters = {
          statusCodes = [ "400-599" ];
          retryAttempts = true;
          minDuration = "250ms";
        };
        fields = {
          defaultMode = "keep";
          headers = {
            defaultMode = "drop";
            names."User-Agent" = "redact";
          };
        };
      };

      metrics = {
        addInternals = true;
        prometheus = {
          entryPoint = "metrics";
          addEntryPointsLabels = true;
          addRoutersLabels = true;
          addServicesLabels = true;
          buckets = [
            0.05
            0.1
            0.25
            0.5
            1.0
            2.5
            5.0
          ];
        };
      };

      entryPoints = {
        ping = {
          address = "127.0.0.1:${toString homolab.ports.traefikPing}";
        };

        metrics = {
          address = "127.0.0.1:${toString homolab.ports.traefikMetrics}";
        };

        web = {
          address = ":80";

          forwardedHeaders.trustedIPs = trustedProxyCidrs;
        };

        websecure = {
          address = ":443";

          forwardedHeaders.trustedIPs = trustedProxyCidrs;

          http.tls.certResolver = "letsencrypt";
        };
      };

      ping.entryPoint = "ping";

      providers.file.watch = true;
    };

    dynamicConfigOptions = {
      http.middlewares = {
        authelia.forwardAuth = {
          address = "http://127.0.0.1:${toString homolab.ports.authelia}/api/verify?rd=https%3A%2F%2F${homolab.domains.auth}%2F";
          maxResponseBodySize = 65536;
          trustForwardHeader = true;
          authResponseHeaders = [
            "Remote-User"
            "Remote-Groups"
            "Remote-Email"
            "Remote-Name"
          ];
        };

        redirect-to-https.redirectScheme = {
          scheme = "https";
          permanent = true;
        };

        technitium-dns-slash.redirectRegex = {
          regex = "^(https?://[^/]+)/dns$";
          replacement = "\${1}/dns/";
          permanent = true;
        };

        npu-youtube.redirectRegex = {
          regex = "^https?://${npuHostRegex}/.*";
          replacement = "https://youtu.be/s461yhBc1wo";
          permanent = true;
        };

        technitium-strip-dns.stripPrefix.prefixes = [ "/dns" ];
      };

      http.routers = {
        npu-http = {
          rule = mkHostRule homolab.domains.npu;
          entryPoints = [ "web" ];

          middlewares = [ "npu-youtube@file" ];
          service = "noop@internal";
        };

        npu = {
          rule = mkHostRule homolab.domains.npu;
          entryPoints = [ "websecure" ];

          middlewares = [ "npu-youtube@file" ];
          service = "noop@internal";
          tls.certResolver = "letsencrypt";
        };

        authelia-http = {
          rule = "Host(`${homolab.domains.auth}`)";
          entryPoints = [ "web" ];

          middlewares = [ "redirect-to-https@file" ];
          service = "noop@internal";
        };

        authelia = {
          rule = "Host(`${homolab.domains.auth}`)";
          entryPoints = [ "websecure" ];

          service = "authelia";
          tls.certResolver = "letsencrypt";
        };

        omniroute-http = {
          rule = mkHostRule homolab.domains.omniroute;
          entryPoints = [ "web" ];

          middlewares = [ "redirect-to-https@file" ];
          service = "noop@internal";
        };

        omniroute-api = {
          rule = mkHostPathRule homolab.domains.omniroute "PathPrefix(`/v1`)";
          entryPoints = [ "websecure" ];
          priority = 1000;

          service = "omniroute-api";
          tls.certResolver = "letsencrypt";
        };

        omniroute = {
          rule = mkHostRule homolab.domains.omniroute;
          entryPoints = [ "websecure" ];

          service = "omniroute";
          tls.certResolver = "letsencrypt";
        };

        grafana-http = {
          rule = mkPrivateHostRule homolab.domains.grafana;
          entryPoints = [ "web" ];

          middlewares = [ "redirect-to-https@file" ];
          service = "noop@internal";
        };

        grafana = {
          rule = mkPrivateHostRule homolab.domains.grafana;
          entryPoints = [ "websecure" ];

          middlewares = [ "authelia@file" ];
          service = "grafana";
          tls.certResolver = "letsencrypt";
        };

        traefik-http = {
          rule = mkPrivateHostRule homolab.domains.traefik;
          entryPoints = [ "web" ];

          middlewares = [ "redirect-to-https@file" ];
          service = "noop@internal";
        };

        traefik = {
          rule = mkPrivateHostRule homolab.domains.traefik;
          entryPoints = [ "websecure" ];

          middlewares = [ "authelia@file" ];
          service = "api@internal";
          tls.certResolver = "letsencrypt";
        };

        technitium-short-http = {
          rule = mkPrivateHostRule technitiumHost;
          entryPoints = [ "web" ];

          middlewares = [ "redirect-to-https@file" ];
          service = "noop@internal";
        };

        technitium-short = {
          rule = mkPrivateHostRule technitiumHost;
          entryPoints = [ "websecure" ];

          middlewares = [ "authelia@file" ];
          service = "technitium";
          tls.certResolver = "letsencrypt";
        };

        technitium-short-doh = {
          rule = mkPrivateHostPathRule technitiumHost "Path(`/dns-query`)";
          entryPoints = [ "websecure" ];
          priority = 120;

          service = "technitium-doh";
          tls.certResolver = "letsencrypt";
        };

        dynacat-http = {
          rule = mkPrivateHostRule homolab.domains.home;
          entryPoints = [ "web" ];

          middlewares = [ "redirect-to-https@file" ];
          service = "noop@internal";
        };

        dynacat = {
          rule = mkPrivateHostRule homolab.domains.home;
          entryPoints = [ "websecure" ];

          middlewares = [ "authelia@file" ];
          service = "dynacat";
          tls.certResolver = "letsencrypt";
        };

        dev-ports = {
          rule = devPortRule;
          entryPoints = [ "websecure" ];

          service = "dev-port-proxy";
          tls = devPortTls;
        };
      };

      http.services = {
        authelia.loadBalancer.servers = [
          { url = "http://127.0.0.1:${toString homolab.ports.authelia}"; }
        ];
        omniroute-api.loadBalancer.servers = [
          { url = "http://${homolab.network.lan.address}:${toString homolab.ports.omnirouteApi}"; }
        ];
        omniroute.loadBalancer.servers = [
          { url = "http://127.0.0.1:${toString homolab.ports.omnirouteDashboard}"; }
        ];
        grafana.loadBalancer.servers = [ { url = "http://127.0.0.1:${toString homolab.ports.grafana}"; } ];
        technitium.loadBalancer.servers = [
          { url = "http://127.0.0.1:${toString homolab.ports.technitium}"; }
        ];
        technitium-doh.loadBalancer.servers = [
          { url = "http://127.0.0.1:${toString homolab.ports.technitiumDoh}"; }
        ];
        dynacat.loadBalancer.servers = [
          { url = "http://127.0.0.1:${toString homolab.ports.dynacat}"; }
        ];
        dev-port-proxy.loadBalancer.servers = [
          { url = "http://127.0.0.1:${toString homolab.ports.devPortProxy}"; }
        ];
      };
    };
  };

  systemd.services.traefik.serviceConfig = {
    EnvironmentFile = "-/run/traefik/cloudflare.env";
    ExecStartPre = "${pkgs.writeShellScript "traefik-cloudflare-env" ''
      set -euo pipefail

      token="$(${pkgs.coreutils}/bin/tr -d '\r\n' < ${config.sops.secrets."cloudflare-ddns-key".path})"
      if [ -z "$token" ]; then
        printf 'Cloudflare DNS API token is empty\n' >&2
        exit 1
      fi

      umask 0077
      {
        printf 'CF_DNS_API_TOKEN=%s\n' "$token"
        printf 'CLOUDFLARE_DNS_API_TOKEN=%s\n' "$token"
      } > /run/traefik/cloudflare.env
    ''}";
  };
}
