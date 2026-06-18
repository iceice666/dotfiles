{
  homolab,
  lib,
  pkgs,
  ...
}:

let
  dynacatPort = homolab.ports.dynacat;
  dynacatStateDir = "/var/lib/dynacat";

  dynacatPackage = pkgs.buildGoModule rec {
    pname = "dynacat";
    version = "2.2.2";

    src = pkgs.fetchFromGitHub {
      owner = "Panonim";
      repo = pname;
      rev = version;
      hash = "sha256-kPUv84yI4LPkoaiVLnBtUi5ecbLC0Is9+9jD00xAmDw=";
    };

    vendorHash = "sha256-7YfGV8ULD2eN3AtzYI18G9/UlpamT3fqjnbvkrCOa14=";
    ldflags = [ "-s -w -X github.com/Panonim/dynacat/internal/dynacat.buildVersion=${version}" ];
    meta.mainProgram = pname;
  };

  yamlFormat = pkgs.formats.yaml { };
  mkLocalUrl = port: path: "http://127.0.0.1:${toString port}${path}";
  mkHomolabUrl = port: path: "http://${homolab.hosts.homolab.tailnet}:${toString port}${path}";
  mkGatewayUrl = port: path: "http://${homolab.hosts.gateway.tailnet}:${toString port}${path}";

  # Prometheus instant-query helpers
  promUrl = "http://127.0.0.1:${toString homolab.ports.prometheus}/api/v1/query";
  mkPromReq = q: {
    url = promUrl;
    parameters.query = q;
  };

  cpuExpr =
    inst: ''100*(1-avg(rate(node_cpu_seconds_total{job="node",mode="idle",instance="${inst}"}[5m])))'';
  memExpr =
    inst:
    ''100*(1-node_memory_MemAvailable_bytes{job="node",instance="${inst}"}/node_memory_MemTotal_bytes{job="node",instance="${inst}"})'';
  diskExpr =
    inst:
    ''100*(1-node_filesystem_avail_bytes{job="node",instance="${inst}",mountpoint="/"}/node_filesystem_size_bytes{job="node",instance="${inst}",mountpoint="/"})'';
  uptimeExpr = inst: ''(time()-node_boot_time_seconds{job="node",instance="${inst}"})/86400'';

  # Build a custom-api host panel querying Prometheus.
  # extraSubreqs: attrset of additional subrequests merged into the base four.
  # extraRows: HTML <li> fragments appended inside the <ul> before closing.
  mkHostPanel = name: extraSubreqs: extraRows: {
    type = "custom-api";
    title = name;
    cache = "30s";
    url = promUrl;
    parameters.query = cpuExpr name;
    subrequests = {
      mem = mkPromReq (memExpr name);
      disk = mkPromReq (diskExpr name);
      uptime = mkPromReq (uptimeExpr name);
    }
    // extraSubreqs;
    template = ''
      {{ if .JSON.Exists "data.result.0" }}
      <ul class="list list-gap-10 list-with-separator">
        <li class="flex justify-between"><span>CPU</span><span class="color-highlight">{{ printf "%.0f" (.JSON.Float "data.result.0.value.1") }}%</span></li>
        <li class="flex justify-between"><span>Mem</span><span class="color-highlight">{{ printf "%.0f" ((.Subrequest "mem").JSON.Float "data.result.0.value.1") }}%</span></li>
        <li class="flex justify-between"><span>Disk</span><span class="color-highlight">{{ printf "%.0f" ((.Subrequest "disk").JSON.Float "data.result.0.value.1") }}%</span></li>
        <li class="flex justify-between"><span>Uptime</span><span class="color-highlight">{{ printf "%.1f" ((.Subrequest "uptime").JSON.Float "data.result.0.value.1") }}d</span></li>
    ''
    + extraRows
    + ''
      </ul>
      {{ else }}
      <p class="color-subdue">down / no data</p>
      {{ end }}
    '';
  };

  homolabPanel =
    mkHostPanel "homolab"
      {
        llama = mkPromReq ''min(probe_success{job="llama-swap-blackbox",instance="homolab"})'';
      }
      ''<li class="flex justify-between"><span>LLM</span><span class="color-highlight">{{ if gt ((.Subrequest "llama").JSON.Float "data.result.0.value.1") 0.5 }}up{{ else }}down{{ end }}</span></li>'';

  lumoPanel =
    mkHostPanel "lumo"
      {
        targets = mkPromReq ''count(up{job="node"} == 1)'';
      }
      ''<li class="flex justify-between"><span>Targets</span><span class="color-highlight">{{ printf "%.0f" ((.Subrequest "targets").JSON.Float "data.result.0.value.1") }} up</span></li>'';

  gatewayPanel =
    mkHostPanel "gateway"
      {
        traefik = mkPromReq ''sum(rate(traefik_entrypoint_requests_total{instance="gateway"}[5m]))'';
      }
      ''<li class="flex justify-between"><span>Req/s</span><span class="color-highlight">{{ printf "%.1f" ((.Subrequest "traefik").JSON.Float "data.result.0.value.1") }}</span></li>'';

  gceDnsPanel =
    mkHostPanel "gce-dns"
      {
        dnsRate = mkPromReq ''sum(rate(blocky_query_total{instance="gce-dns"}[5m]))'';
        cache = mkPromReq ''sum(blocky_cache_entry_count{instance="gce-dns"})'';
      }
      ''
        <li class="flex justify-between"><span>DNS/s</span><span class="color-highlight">{{ printf "%.1f" ((.Subrequest "dnsRate").JSON.Float "data.result.0.value.1") }}</span></li>
        <li class="flex justify-between"><span>Cache</span><span class="color-highlight">{{ printf "%.0f" ((.Subrequest "cache").JSON.Float "data.result.0.value.1") }}</span></li>
      '';

  serviceIcons = {
    authelia = "si:authelia";
    cliproxyapi = "si:openai";
    grafana = "si:grafana";
    proxy = "si:traefikproxy";
    shimmy = "si:openai";
  };

  monitorSiteDefaults = {
    timeout = "5s";
    "alt-status-codes" = [
      302
      401
      403
    ];
  };

  mkMonitorSite =
    title: icon: url: checkUrl:
    monitorSiteDefaults
    // {
      inherit icon title url;
      "check-url" = checkUrl;
    };

  mkMonitorWidget = title: sites: {
    type = "monitor";
    inherit title sites;
    cache = "1m";
    "update-interval" = "2m";
  };

  dynacatConfig = yamlFormat.generate "dynacat.yml" {
    server = {
      port = dynacatPort;
      proxied = true;
    };

    branding = {
      "hide-footer" = true;
      "logo-text" = "HL";
      "app-name" = homolab.hostName;
    };

    theme = {
      "background-color" = "295 10 23";
      "primary-color" = "10 45 71";
      "positive-color" = "156 6 69";
      "negative-color" = "11 37 64";
      "contrast-multiplier" = 1.1;
      "text-saturation-multiplier" = 1;
      "disable-picker" = true;
    };

    pages = [
      {
        name = "system";
        width = "wide";
        columns = [
          {
            size = "full";
            widgets = [
              {
                type = "split-column";
                "max-columns" = 4;
                widgets = [
                  homolabPanel
                  lumoPanel
                  gatewayPanel
                  gceDnsPanel
                ];
              }
            ];
          }
        ];
      }
      {
        name = "services";
        width = "wide";
        columns = [
          {
            size = "full";
            widgets = [
              {
                type = "split-column";
                "max-columns" = 3;
                widgets = [
                  (mkMonitorWidget "Public" [
                    (mkMonitorSite "CLIProxyAPI" serviceIcons.cliproxyapi "${homolab.urls.cliproxyapi}/management.html" (
                      mkHomolabUrl homolab.ports.cliproxyapi "/healthz"
                    ))
                  ])
                  (mkMonitorWidget "Infra" [
                    (mkMonitorSite "Traefik" serviceIcons.proxy homolab.urls.traefik (
                      mkGatewayUrl homolab.ports.traefikPing "/ping"
                    ))
                    (mkMonitorSite "Authelia" serviceIcons.authelia homolab.urls.auth (
                      mkGatewayUrl homolab.ports.authelia ""
                    ))
                    (mkMonitorSite "Shimmy (on-demand)" serviceIcons.shimmy "${homolab.ai.tailnetBaseUrl}/health" (
                      "${homolab.ai.tailnetBaseUrl}/health"
                    ))
                    (mkMonitorSite "Grafana" serviceIcons.grafana homolab.urls.grafana (
                      mkLocalUrl homolab.ports.grafana "/api/health"
                    ))
                  ])
                ];
              }
            ];
          }
        ];
      }
    ];
  };

  dynacatService = pkgs.writeText "lumo-dynacat" ''
    #!/sbin/openrc-run
    name="lumo-dynacat"
    description="Lumo Dynacat dashboard"
    supervisor=supervise-daemon
    command="${dynacatPackage}/bin/dynacat"
    command_args="-config ${dynacatConfig}"
    command_user="dynacat:dynacat"
    directory="${dynacatStateDir}"
    output_log="/var/log/lumo/dynacat.log"
    error_log="/var/log/lumo/dynacat.log"
    respawn_delay=5
    respawn_max=0
    export BIND="0.0.0.0"

    depend() {
      need net
      after lumo-grafana
    }

    start_pre() {
      checkpath -f -m 0640 -o dynacat:dynacat /var/log/lumo/dynacat.log
      checkpath -d -m 0750 -o dynacat:dynacat ${dynacatStateDir}
    }
  '';
in
{
  home.packages = [ dynacatPackage ];

  home.activation.lumoDynacat = lib.hm.dag.entryAfter [ "lumoMonitoring" ] ''
    if ! /usr/bin/getent group dynacat >/dev/null; then
      /usr/sbin/addgroup -S dynacat
    fi
    if ! /usr/bin/id dynacat >/dev/null 2>&1; then
      /usr/sbin/adduser -S -D -H -h ${dynacatStateDir} -s /sbin/nologin -G dynacat dynacat
    fi

    install -Dm755 ${dynacatService} /etc/init.d/lumo-dynacat
    /sbin/rc-update add lumo-dynacat default
    /sbin/rc-service lumo-dynacat restart
  '';
}
