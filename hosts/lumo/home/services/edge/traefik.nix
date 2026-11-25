{
  config,
  dotfiles,
  lab,
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

  privateClientRule = "(ClientIP(`127.0.0.1/32`) || ClientIP(`::1/128`) || ClientIP(`${lab.network.lan.cidr}`) || ClientIP(`100.64.0.0/10`) || ClientIP(`fd7a:115c:a1e0::/48`))";

  mkHostRule = host: "Host(`${host}`)";
  mkHostPathRule = host: pathRule: "${mkHostRule host} && ${pathRule}";
  mkPrivateHostRule = host: "${mkHostRule host} && ${privateClientRule}";
  mkPrivateHostPathRule = host: pathRule: "${mkPrivateHostRule host} && ${pathRule}";

  # LAN-only: excludes the tailnet ranges, and Cloudflare-proxied requests
  # arrive from Cloudflare addresses. No tailnet node advertises a subnet
  # route, so tailnet traffic is never SNATed to a LAN source.
  mkLanHostRule = host: "${mkHostRule host} && ClientIP(`${lab.network.lan.cidr}`)";

  # Mainsail/Moonraker web UI on the 3D printer.
  printerUrl = "http://192.168.1.90";

  npuHostRegex = builtins.replaceStrings [ "." ] [ "\\." ] lab.domains.npu;

  yamlFormat = pkgs.formats.yaml { };

  staticConfig = yamlFormat.generate "traefik-static.yml" {
    global = {
      checkNewVersion = false;
      sendAnonymousUsage = false;
    };

    certificatesResolvers.letsencrypt.acme = {
      email = lab.contact.adminEmail;
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

    # Drop request headers whose name aliases another (Remote_User, Remote.User,
    # …) so a client cannot smuggle a lookalike past forward-auth identity
    # headers; only letters, digits and dashes survive.
    entryPoints =
      lib.mapAttrs (_: ep: lib.recursiveUpdate { http.aliasHeadersStrategy = "delete"; } ep)
        {
          # Only local Prometheus and the smoke check consume these; the retired
          # gateway Pi was the last LAN scraper.
          ping.address = "127.0.0.1:${toString lab.ports.traefikPing}";
          metrics.address = "127.0.0.1:${toString lab.ports.traefikMetrics}";

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

  # Attached to every websecure router so no route forgets it. Redirect-only
  # `web` routers are excluded: the headers belong on the HTTPS response.
  securityHeadersMiddleware = "security-headers@file";
  withSecurityHeaders = lib.mapAttrs (
    _: router:
    if router.entryPoints == [ "websecure" ] then
      router // { middlewares = [ securityHeadersMiddleware ] ++ (router.middlewares or [ ]); }
    else
      router
  );

  dynamicConfig = yamlFormat.generate "traefik-dynamic.yml" {
    tls.options.default = {
      minVersion = "VersionTLS12";
      sniStrict = true;
      # TLS 1.3 suites are fixed by Go; this list only constrains TLS 1.2.
      cipherSuites = [
        "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256"
        "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"
        "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384"
        "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
        "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305"
        "TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305"
      ];
      curvePreferences = [
        "X25519"
        "CurveP256"
      ];
    };

    http.middlewares = {
      # SAMEORIGIN rather than DENY: the Authelia portal and Umami embed
      # same-origin frames. No HSTS preload; every subdomain already
      # redirects to HTTPS, so includeSubdomains is safe.
      security-headers.headers = {
        stsSeconds = 31536000;
        stsIncludeSubdomains = true;
        contentTypeNosniff = true;
        referrerPolicy = "strict-origin-when-cross-origin";
        customFrameOptionsValue = "SAMEORIGIN";
      };

      authelia.forwardAuth = {
        address = "http://127.0.0.1:${toString lab.ports.authelia}/api/verify?rd=https%3A%2F%2F${lab.domains.auth}%2F";
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

    http.routers = withSecurityHeaders (
      lib.filterAttrs
        (
          name: _:
          config.lumo.forgejoWoodpecker.enable
          || !(builtins.elem name [
            "forgejo-http"
            "forgejo"
            "woodpecker-http"
            "woodpecker"
          ])
        )
        {
          npu-http = {
            rule = mkHostRule lab.domains.npu;
            entryPoints = [ "web" ];
            middlewares = [ "npu-youtube@file" ];
            service = "noop@internal";
          };

          npu = {
            rule = mkHostRule lab.domains.npu;
            entryPoints = [ "websecure" ];
            middlewares = [ "npu-youtube@file" ];
            service = "noop@internal";
            tls.certResolver = "letsencrypt";
          };

          authelia-http = {
            rule = "Host(`${lab.domains.auth}`)";
            entryPoints = [ "web" ];
            middlewares = [ "redirect-to-https@file" ];
            service = "noop@internal";
          };

          authelia = {
            rule = "Host(`${lab.domains.auth}`)";
            entryPoints = [ "websecure" ];
            service = "authelia";
            tls.certResolver = "letsencrypt";
          };

          # The whole CPA host is private: agent clients sit on the tailnet and
          # Blocky resolves the name to lumo's tailnet address, so nothing
          # legitimate arrives through Cloudflare.
          cliproxyapi-http = {
            rule = mkPrivateHostRule lab.domains.cliproxyapi;
            entryPoints = [ "web" ];
            middlewares = [ "redirect-to-https@file" ];
            service = "noop@internal";
          };

          # /v1/* — API, clients authenticate with their own API key.
          # Explicit priority (matches umami-api) so this always wins over the
          # broader Authelia-gated `cliproxyapi` dashboard router below.
          cliproxyapi-api = {
            rule = mkPrivateHostPathRule lab.domains.cliproxyapi "PathPrefix(`/v1`)";
            entryPoints = [ "websecure" ];
            priority = 1000;
            service = "cliproxyapi";
            tls.certResolver = "letsencrypt";
          };
          # Same-origin Keeper route must outrank the broader CPAMC dashboard.
          cliproxyapi-keeper = {
            rule = mkPrivateHostPathRule lab.domains.cliproxyapi "(Path(`/keeper`) || PathPrefix(`/keeper/`))";
            entryPoints = [ "websecure" ];
            priority = 1000;
            middlewares = [ "authelia@file" ];
            service = "cliproxyapi-usage-keeper";
            tls.certResolver = "letsencrypt";
          };

          # Dashboard — Authelia protected
          cliproxyapi = {
            rule = mkPrivateHostRule lab.domains.cliproxyapi;
            entryPoints = [ "websecure" ];
            middlewares = [ "authelia@file" ];
            service = "cliproxyapi";
            tls.certResolver = "letsencrypt";
          };
          forgejo-http = {
            rule = mkHostRule lab.domains.forgejo;
            entryPoints = [ "web" ];
            middlewares = [ "redirect-to-https@file" ];
            service = "noop@internal";
          };

          forgejo = {
            rule = mkHostRule lab.domains.forgejo;
            entryPoints = [ "websecure" ];
            service = "forgejo";
            tls.certResolver = "letsencrypt";
          };

          woodpecker-http = {
            rule = mkHostRule lab.domains.woodpecker;
            entryPoints = [ "web" ];
            middlewares = [ "redirect-to-https@file" ];
            service = "noop@internal";
          };

          woodpecker = {
            rule = mkHostRule lab.domains.woodpecker;
            entryPoints = [ "websecure" ];
            service = "woodpecker";
            tls.certResolver = "letsencrypt";
          };

          umami-http = {
            rule = mkHostRule lab.domains.analytics;
            entryPoints = [ "web" ];
            middlewares = [ "redirect-to-https@file" ];
            service = "noop@internal";
          };

          # Public Umami collection endpoints plus the authenticated stats endpoints
          # consumed by Dynamic's Cloudflare Worker-side visit counters.
          umami-api = {
            rule = mkHostPathRule lab.domains.analytics "(Path(`/script.js`) || Path(`/api/send`) || Path(`/api/auth/login`) || PathRegexp(`/api/websites/[a-zA-Z0-9-]+/(stats|pageviews|metrics/expanded)`))";
            entryPoints = [ "websecure" ];
            priority = 1000;
            service = "umami";
            tls.certResolver = "letsencrypt";
          };

          # Dashboard — Authelia protected; Umami still enforces its own app login.
          umami = {
            rule = mkPrivateHostRule lab.domains.analytics;
            entryPoints = [ "websecure" ];
            middlewares = [ "authelia@file" ];
            service = "umami";
            tls.certResolver = "letsencrypt";
          };

          blocky-doh = {
            rule = mkPrivateHostPathRule lab.domains.dns "Path(`/dns-query`)";
            entryPoints = [ "websecure" ];
            priority = 120;
            service = "blocky";
            tls.certResolver = "letsencrypt";
          };

          traefik-http = {
            rule = mkPrivateHostRule lab.domains.traefik;
            entryPoints = [ "web" ];
            middlewares = [ "redirect-to-https@file" ];
            service = "noop@internal";
          };

          traefik = {
            rule = mkPrivateHostRule lab.domains.traefik;
            entryPoints = [ "websecure" ];
            middlewares = [ "authelia@file" ];
            service = "api@internal";
            tls.certResolver = "letsencrypt";
          };

          dynacat-http = {
            rule = mkPrivateHostRule lab.domains.home;
            entryPoints = [ "web" ];
            middlewares = [ "redirect-to-https@file" ];
            service = "noop@internal";
          };

          dynacat = {
            rule = mkPrivateHostRule lab.domains.home;
            entryPoints = [ "websecure" ];
            middlewares = [ "authelia@file" ];
            service = "dynacat";
            tls.certResolver = "letsencrypt";
          };

          learnharness-http = {
            rule = mkPrivateHostRule lab.domains.learnharness;
            entryPoints = [ "web" ];
            middlewares = [ "redirect-to-https@file" ];
            service = "noop@internal";
          };

          # LearnHarness has no user authentication of its own (browser mode is
          # a trusted shared server), so the whole host sits behind Authelia.
          learnharness = {
            rule = mkPrivateHostRule lab.domains.learnharness;
            entryPoints = [ "websecure" ];
            middlewares = [ "authelia@file" ];
            service = "learnharness";
            tls.certResolver = "letsencrypt";
          };

          printer-http = {
            rule = mkLanHostRule lab.domains.printer;
            entryPoints = [ "web" ];
            middlewares = [ "redirect-to-https@file" ];
            service = "noop@internal";
          };

          printer = {
            rule = mkLanHostRule lab.domains.printer;
            entryPoints = [ "websecure" ];
            service = "printer";
            tls.certResolver = "letsencrypt";
          };
        }
    );

    http.services =
      lib.filterAttrs
        (
          name: _:
          config.lumo.forgejoWoodpecker.enable
          || !(builtins.elem name [
            "forgejo"
            "woodpecker"
          ])
        )
        {
          authelia.loadBalancer.servers = [
            { url = "http://127.0.0.1:${toString lab.ports.authelia}"; }
          ];
          cliproxyapi.loadBalancer.servers = [
            { url = "http://127.0.0.1:${toString lab.ports.cliproxyapi}"; }
          ];
          cliproxyapi-usage-keeper.loadBalancer.servers = [
            { url = "http://127.0.0.1:${toString lab.ports.cliproxyapiUsageKeeper}"; }
          ];
          forgejo.loadBalancer.servers = [
            { url = "http://127.0.0.1:${toString lab.ports.forgejo}"; }
          ];
          woodpecker.loadBalancer.servers = [
            { url = "http://127.0.0.1:${toString lab.ports.woodpecker}"; }
          ];
          umami.loadBalancer.servers = [
            { url = "http://127.0.0.1:${toString lab.ports.umami}"; }
          ];
          blocky.loadBalancer.servers = [
            { url = "http://127.0.0.1:4000"; }
          ];
          dynacat.loadBalancer.servers = [
            { url = "http://127.0.0.1:${toString lab.ports.dynacat}"; }
          ];
          learnharness.loadBalancer.servers = [
            { url = "http://127.0.0.1:${toString lab.ports.learnharness}"; }
          ];
          printer.loadBalancer.servers = [ { url = printerUrl; } ];
        };
  };

  # Passing the Cloudflare token via `supervise_daemon_args="-e VAR=<value>"`
  # (as authelia.nix does with *_FILE paths) is not viable here: lego's
  # Cloudflare DNS provider only reads the token from an env var, not a file,
  # and `-e VAR=<value>` becomes literal argv on supervise-daemon's own
  # command line, which is visible to any local reader of `ps`/`/proc`. Read
  # the secret and `exec` traefik from a small wrapper instead, so the token
  # only ever lives in traefik's own environment, never in argv.
  #
  # The wrapper starts as root (the sops secret is root-only), then drops to
  # the unprivileged `traefik` account through setpriv, keeping only an
  # ambient CAP_NET_BIND_SERVICE for :80/:443. Alpine's OpenRC is built
  # without libcap, so supervise-daemon cannot grant capabilities itself, and
  # this avoids lowering ip_unprivileged_port_start system-wide.
  traefikWrapper = pkgs.writeShellScript "lumo-traefik-wrapper" ''
    set -eu
    token="$(tr -d '\r\n' < '${cfKeyPath}')"
    if [ -z "$token" ]; then
      echo "Cloudflare API token is empty" >&2
      exit 1
    fi
    export CF_DNS_API_TOKEN="$token"
    export CLOUDFLARE_DNS_API_TOKEN="$token"
    exec ${pkgs.util-linux}/bin/setpriv \
      --reuid traefik --regid traefik --init-groups \
      --bounding-set -all,+net_bind_service \
      --inh-caps -all,+net_bind_service \
      --ambient-caps -all,+net_bind_service \
      --no-new-privs \
      -- ${traefikPackage}/bin/traefik --configFile=${staticConfig}
  '';

  traefikService = pkgs.writeText "lumo-traefik" ''
    #!/sbin/openrc-run
    name="lumo-traefik"
    description="Lumo Traefik reverse proxy"
    supervisor=supervise-daemon
    command="${traefikWrapper}"
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
      checkpath -d -m 0700 -o traefik:traefik /var/lib/traefik
      # Migrate acme.json written by earlier root-run generations.
      chown -R traefik:traefik /var/lib/traefik
      checkpath -f -m 0640 -o traefik:traefik /var/log/lumo/traefik.log
    }
  '';
in
{
  sops.secrets.cloudflare-traefik-key = {
    sopsFile = dotfiles + /sensitive/hosts/lumo/cloudflare-ddns.key;
    format = "binary";
    mode = "0400";
  };

  home.activation.lumoTraefik = lib.hm.dag.entryAfter [ "sopsAlpine" "lumoAuthelia" "lumoBlocky" ] ''
    if ! /usr/bin/getent group traefik >/dev/null; then
      /usr/sbin/addgroup -S traefik
    fi
    if ! /usr/bin/id traefik >/dev/null 2>&1; then
      /usr/sbin/adduser -S -D -H -h /var/lib/traefik -s /sbin/nologin -G traefik traefik
    fi

    install -Dm755 ${traefikService} /etc/init.d/lumo-traefik
    /sbin/rc-update add lumo-traefik default
    /sbin/rc-service lumo-traefik restart
  '';
}
