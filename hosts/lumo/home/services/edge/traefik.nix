{
  config,
  dotfiles,
  homolab,
  lib,
  pkgs,
  unstablePkgs,
  ...
}:

let
  traefikPackage = unstablePkgs.traefik;

  cfKeyPath = config.sops.secrets.cloudflare-traefik-key.path;

  trustedProxyCidrs = [
    "127.0.0.1/32"
    "::1/128"
  ];

  testWildcardDomain = "test.${homolab.domains.root}";

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

  yamlFormat = pkgs.formats.yaml { };

  staticConfig = yamlFormat.generate "traefik-static.yml" {
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
      ping.address = "0.0.0.0:${toString homolab.ports.traefikPing}";
      metrics.address = "0.0.0.0:${toString homolab.ports.traefikMetrics}";

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

    providers.file = {
      filename = "${dynamicConfig}";
      watch = false;
    };
  };

  dynamicConfig = yamlFormat.generate "traefik-dynamic.yml" {
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

      npu-youtube.redirectRegex = {
        regex = "^https?://${npuHostRegex}/.*";
        replacement = "https://youtu.be/s461yhBc1wo";
        permanent = true;
      };
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

      cliproxyapi-http = {
        rule = mkHostRule homolab.domains.cliproxyapi;
        entryPoints = [ "web" ];
        middlewares = [ "redirect-to-https@file" ];
        service = "noop@internal";
      };

      # /v1/* — public API, clients authenticate with their own API key
      cliproxyapi-api = {
        rule = mkHostPathRule homolab.domains.cliproxyapi "PathPrefix(`/v1`)";
        entryPoints = [ "websecure" ];
        service = "cliproxyapi";
        tls.certResolver = "letsencrypt";
      };

      # Dashboard — Authelia protected
      cliproxyapi = {
        rule = mkHostRule homolab.domains.cliproxyapi;
        entryPoints = [ "websecure" ];
        middlewares = [ "authelia@file" ];
        service = "cliproxyapi";
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

      blocky-doh = {
        rule = mkPrivateHostPathRule homolab.domains.dns "Path(`/dns-query`)";
        entryPoints = [ "websecure" ];
        priority = 120;
        service = "blocky";
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
      cliproxyapi.loadBalancer.servers = [
        { url = "http://${homolab.hosts.lumo.lan}:${toString homolab.ports.cliproxyapi}"; }
      ];
      grafana.loadBalancer.servers = [
        { url = "http://${homolab.hosts.lumo.lan}:${toString homolab.ports.grafana}"; }
      ];
      blocky.loadBalancer.servers = [
        { url = "http://gce-dns:4000"; }
      ];
      dynacat.loadBalancer.servers = [
        { url = "http://${homolab.hosts.lumo.lan}:${toString homolab.ports.dynacat}"; }
      ];
      dev-port-proxy.loadBalancer.servers = [
        { url = "http://${homolab.hosts.lumo.lan}:${toString homolab.ports.devPortProxy}"; }
      ];
    };
  };

  traefikService = pkgs.writeText "lumo-traefik" ''
    #!/sbin/openrc-run
    name="lumo-traefik"
    description="Lumo Traefik reverse proxy"
    supervisor=supervise-daemon
    command="${traefikPackage}/bin/traefik"
    command_args="--configFile=${staticConfig}"
    directory="/var/lib/traefik"
    output_log="/var/log/lumo/traefik.log"
    error_log="/var/log/lumo/traefik.log"
    respawn_delay=5
    respawn_max=0

    depend() {
      need net
      after lumo-authelia lumo-cloudflare-ips
    }

    start_pre() {
      checkpath -d -m 0755 -o root:root /var/log/lumo
      checkpath -d -m 0700 -o root:root /var/lib/traefik
      checkpath -f -m 0640 -o root:root /var/log/lumo/traefik.log

      token="$(tr -d '\r\n' < '${cfKeyPath}')"
      if [ -z "$token" ]; then
        eend 1 "Cloudflare API token is empty"
        return 1
      fi
      # Pass token via supervise-daemon -e flag (Cloudflare tokens are alphanumeric).
      supervise_daemon_args="-e CF_DNS_API_TOKEN=$token -e CLOUDFLARE_DNS_API_TOKEN=$token"
    }
  '';
in
{
  sops.secrets.cloudflare-traefik-key = {
    sopsFile = dotfiles + /sensitive/hosts/lumo/cloudflare-ddns.key;
    format = "binary";
    mode = "0400";
  };

  home.activation.lumoTraefik = lib.hm.dag.entryAfter [ "sopsAlpine" "lumoAuthelia" ] ''
    install -Dm755 ${traefikService} /etc/init.d/lumo-traefik
    /sbin/rc-update add lumo-traefik default
    /sbin/rc-service lumo-traefik restart
  '';
}
