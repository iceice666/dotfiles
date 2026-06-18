{
  config,
  dotfiles,
  homolab,
  lib,
  pkgs,
  ...
}:

let
  blackboxPort = 19115;
  nodeExporterPort = 19100;

  grafanaPlugins = pkgs.buildEnv {
    name = "lumo-grafana-plugins";
    paths = [ pkgs.grafanaPlugins.yesoreyeram-infinity-datasource ];
    pathsToLink = [ "/share/grafana/plugins" ];
  };

  blackboxConfig = (pkgs.formats.yaml { }).generate "blackbox.yml" {
    modules.http_2xx = {
      prober = "http";
      timeout = "10s";
      http = {
        method = "GET";
        preferred_ip_protocol = "ip4";
        valid_status_codes = [ 200 ];
      };
    };
  };

  prometheusRules = pkgs.writeText "lumo-alert-rules.yml" ''
    groups:
      # llama-swap probe data is collected (see llama-swap-blackbox scrape job) but
      # no alerts fire: homolab is an on-demand GPU worker that sleeps when idle,
      # so a failing /health probe is the normal state, not a fault.
      - name: host-resource.rules
        rules:
          - alert: HostHighCpuUsage
            expr: 100 * (1 - avg by (instance) (rate(node_cpu_seconds_total{job="node", mode="idle"}[5m]))) > 90
            for: 15m
            labels:
              severity: warning
              service: host
            annotations:
              summary: "{{ $labels.instance }} CPU usage is high"
          - alert: HostHighMemoryUsage
            expr: 100 * (1 - node_memory_MemAvailable_bytes{job="node"} / node_memory_MemTotal_bytes{job="node"}) > 90
            for: 15m
            labels:
              severity: warning
              service: host
            annotations:
              summary: "{{ $labels.instance }} memory usage is high"
          - alert: HostLowDiskSpace
            expr: 100 * (1 - node_filesystem_avail_bytes{job="node", fstype!~"tmpfs|ramfs"} / node_filesystem_size_bytes{job="node", fstype!~"tmpfs|ramfs"}) > 85
            for: 30m
            labels:
              severity: warning
              service: host
            annotations:
              summary: "{{ $labels.instance }} filesystem usage is high"
  '';

  prometheusConfig = (pkgs.formats.yaml { }).generate "prometheus.yml" {
    global = {
      scrape_interval = "15s";
      evaluation_interval = "15s";
    };
    rule_files = [ prometheusRules ];
    scrape_configs = [
      {
        job_name = "prometheus";
        static_configs = [
          {
            targets = [ "127.0.0.1:${toString homolab.ports.prometheus}" ];
            labels.instance = "lumo";
          }
        ];
      }
      {
        job_name = "node";
        static_configs = [
          {
            targets = [ "127.0.0.1:${toString nodeExporterPort}" ];
            labels.instance = "lumo";
          }
          {
            targets = [
              "${homolab.hosts.homolab.tailnet}:${toString nodeExporterPort}"
            ];
            labels.instance = homolab.hostName;
          }
          {
            targets = [
              "${homolab.hosts.gateway.tailnet}:${toString nodeExporterPort}"
            ];
            labels.instance = "gateway";
          }
          {
            targets = [ "gce-dns:${toString nodeExporterPort}" ];
            labels.instance = "gce-dns";
          }
        ];
      }
      {
        job_name = "traefik";
        static_configs = [
          {
            targets = [
              "${homolab.hosts.gateway.tailnet}:${toString homolab.ports.traefikMetrics}"
            ];
            labels.instance = "gateway";
          }
        ];
      }
      {
        job_name = "blocky";
        metrics_path = "/metrics";
        static_configs = [
          {
            targets = [ "gce-dns:4000" ];
            labels.instance = "gce-dns";
          }
        ];
      }
      {
        job_name = "cliproxyapi-blackbox";
        metrics_path = "/probe";
        params.module = [ "http_2xx" ];
        static_configs = [
          {
            targets = [
              "http://${homolab.network.lan.address}:${toString homolab.ports.cliproxyapi}/healthz"
            ];
            labels = {
              instance = homolab.hostName;
              service = "cliproxyapi";
            };
          }
        ];
        relabel_configs = [
          {
            source_labels = [ "__address__" ];
            target_label = "__param_target";
          }
          {
            source_labels = [ "__param_target" ];
            target_label = "target";
          }
          {
            target_label = "__address__";
            replacement = "127.0.0.1:${toString blackboxPort}";
          }
        ];
      }
      {
        job_name = "llama-swap-blackbox";
        metrics_path = "/probe";
        params.module = [ "http_2xx" ];
        static_configs = [
          {
            targets = [
              "${homolab.ai.tailnetBaseUrl}/health"
              "${homolab.ai.tailnetOpenaiBaseUrl}/models"
            ];
            labels = {
              instance = homolab.hostName;
              service = "llama-swap";
            };
          }
        ];
        relabel_configs = [
          {
            source_labels = [ "__address__" ];
            target_label = "__param_target";
          }
          {
            source_labels = [ "__param_target" ];
            target_label = "target";
          }
          {
            target_label = "__address__";
            replacement = "127.0.0.1:${toString blackboxPort}";
          }
        ];
      }
    ];
  };

  prometheusService = pkgs.writeText "lumo-prometheus" ''
    #!/sbin/openrc-run
    name="lumo-prometheus"
    description="Lumo Prometheus"
    supervisor=supervise-daemon
    command="${pkgs.prometheus}/bin/prometheus"
    command_args="--config.file=${prometheusConfig} --storage.tsdb.path=/var/lib/prometheus --storage.tsdb.retention.time=30d --web.listen-address=127.0.0.1:${toString homolab.ports.prometheus}"
    command_user="prometheus:prometheus"
    output_log="/var/log/lumo/prometheus.log"
    error_log="/var/log/lumo/prometheus.log"
    respawn_delay=5
    respawn_max=0

    depend() {
      need net
      after lumo-node-exporter lumo-blackbox-exporter
    }

    start_pre() {
      checkpath -f -m 0640 -o prometheus:prometheus /var/log/lumo/prometheus.log
      checkpath -d -m 0750 -o prometheus:prometheus /var/lib/prometheus
      ${pkgs.prometheus.cli}/bin/promtool check config ${prometheusConfig}
      ${pkgs.prometheus.cli}/bin/promtool check rules ${prometheusRules}
    }
  '';

  nodeExporterService = pkgs.writeText "lumo-node-exporter" ''
    #!/sbin/openrc-run
    name="lumo-node-exporter"
    description="Lumo node exporter"
    supervisor=supervise-daemon
    command="${pkgs.prometheus-node-exporter}/bin/node_exporter"
    command_args="--web.listen-address=127.0.0.1:${toString nodeExporterPort} --collector.processes '--collector.filesystem.mount-points-exclude=^/(dev|proc|sys|run/credentials/.+|var/lib/containers/storage/.+)($|/)' '--collector.filesystem.fs-types-exclude=^(autofs|binfmt_misc|bpf|cgroup2?|configfs|debugfs|devpts|devtmpfs|fusectl|hugetlbfs|mqueue|nsfs|overlay|proc|pstore|securityfs|sysfs|tracefs)$'"
    command_user="prometheus:prometheus"
    output_log="/var/log/lumo/node-exporter.log"
    error_log="/var/log/lumo/node-exporter.log"
    respawn_delay=5
    respawn_max=0

    depend() {
      need net
    }

    start_pre() {
      checkpath -f -m 0640 -o prometheus:prometheus /var/log/lumo/node-exporter.log
    }
  '';

  blackboxService = pkgs.writeText "lumo-blackbox-exporter" ''
    #!/sbin/openrc-run
    name="lumo-blackbox-exporter"
    description="Lumo blackbox exporter"
    supervisor=supervise-daemon
    command="${pkgs.prometheus-blackbox-exporter}/bin/blackbox_exporter"
    command_args="--config.file=${blackboxConfig} --web.listen-address=127.0.0.1:${toString blackboxPort}"
    command_user="prometheus:prometheus"
    output_log="/var/log/lumo/blackbox-exporter.log"
    error_log="/var/log/lumo/blackbox-exporter.log"
    respawn_delay=5
    respawn_max=0

    depend() {
      need net
    }

    start_pre() {
      checkpath -f -m 0640 -o prometheus:prometheus /var/log/lumo/blackbox-exporter.log
    }
  '';

  grafanaSecret = config.sops.secrets.grafana-secret-key.path;
  grafanaConfig = (pkgs.formats.ini { }).generate "grafana.ini" {
    analytics = {
      reporting_enabled = false;
      check_for_updates = false;
      check_for_plugin_updates = false;
    };
    server = {
      http_addr = "0.0.0.0";
      http_port = homolab.ports.grafana;
      domain = homolab.domains.grafana;
      enforce_domain = true;
      root_url = "${homolab.urls.grafana}/";
    };
    security = {
      disable_initial_admin_creation = true;
      secret_key = "$__file{/run/lumo-grafana/secret-key}";
    };
    users = {
      allow_sign_up = false;
      auto_assign_org_role = "Editor";
    };
    auth.disable_login_form = true;
    "auth.proxy" = {
      enabled = true;
      header_name = "Remote-User";
      header_property = "username";
      auto_sign_up = true;
      sync_ttl = 15;
      whitelist = homolab.hosts.gateway.lan;
      headers = "Name:Remote-Name Email:Remote-Email Groups:Remote-Groups";
    };
    paths.provisioning = "/etc/lumo-grafana/provisioning";
    plugins.allow_loading_unsigned_plugins = "";
  };

  grafanaDatasource = (pkgs.formats.yaml { }).generate "datasources.yml" {
    apiVersion = 1;
    prune = true;
    datasources = [
      {
        name = "Prometheus";
        uid = "prometheus";
        type = "prometheus";
        url = "http://127.0.0.1:${toString homolab.ports.prometheus}";
        isDefault = true;
        editable = false;
      }
      {
        name = "Infinity";
        uid = "infinity";
        type = "yesoreyeram-infinity-datasource";
        access = "proxy";
        editable = false;
      }
    ];
  };

  grafanaDashboards = (pkgs.formats.yaml { }).generate "dashboards.yml" {
    apiVersion = 1;
    providers = [
      {
        name = "homolab";
        type = "file";
        folder = "Homolab";
        editable = true;
        allowUiUpdates = true;
        options.path = dotfiles + /hosts/homolab/services/edge/grafana-dashboards;
      }
    ];
  };

  grafanaService = pkgs.writeText "lumo-grafana" ''
    #!/sbin/openrc-run
    name="lumo-grafana"
    description="Lumo Grafana"
    supervisor=supervise-daemon
    command="${pkgs.grafana}/bin/grafana"
    command_args="server --homepath ${pkgs.grafana}/share/grafana --config ${grafanaConfig}"
    command_user="grafana:grafana"
    directory="/var/lib/grafana"
    output_log="/var/log/lumo/grafana.log"
    error_log="/var/log/lumo/grafana.log"
    respawn_delay=5
    respawn_max=0
    export GF_PATHS_DATA="/var/lib/grafana"
    export GF_PATHS_LOGS="/var/log/grafana"
    export GF_PATHS_PLUGINS="${grafanaPlugins}/share/grafana/plugins"

    depend() {
      need net
      after lumo-prometheus
    }

    start_pre() {
      checkpath -f -m 0640 -o grafana:grafana /var/log/lumo/grafana.log
      checkpath -d -m 0750 -o grafana:grafana /run/lumo-grafana
      checkpath -d -m 0750 -o grafana:grafana /var/lib/grafana
      checkpath -d -m 0750 -o grafana:grafana /var/log/grafana
      cp ${grafanaSecret} /run/lumo-grafana/secret-key
      chown grafana:grafana /run/lumo-grafana/secret-key
      chmod 0400 /run/lumo-grafana/secret-key
    }
  '';
in
{
  home.packages = [
    pkgs.grafana
    pkgs.prometheus
    pkgs.prometheus-blackbox-exporter
    pkgs.prometheus-node-exporter
  ];

  sops.secrets.grafana-secret-key = {
    sopsFile = dotfiles + /sensitive/hosts/lumo/grafana.yaml;
    key = "secretKey";
    mode = "0400";
  };

  home.activation.lumoMonitoring = lib.hm.dag.entryAfter [ "lumoDirectories" ] ''
    for account in prometheus grafana; do
      if ! /usr/bin/getent group "$account" >/dev/null; then
        /usr/sbin/addgroup -S "$account"
      fi
      if ! /usr/bin/id "$account" >/dev/null 2>&1; then
        /usr/sbin/adduser -S -D -H -h "/var/lib/$account" -s /sbin/nologin -G "$account" "$account"
      fi
    done

    install -d -m 0755 /etc/lumo-grafana/provisioning/datasources
    install -d -m 0755 /etc/lumo-grafana/provisioning/dashboards
    install -Dm644 ${grafanaDatasource} /etc/lumo-grafana/provisioning/datasources/default.yml
    install -Dm644 ${grafanaDashboards} /etc/lumo-grafana/provisioning/dashboards/default.yml

    install -Dm755 ${nodeExporterService} /etc/init.d/lumo-node-exporter
    install -Dm755 ${blackboxService} /etc/init.d/lumo-blackbox-exporter
    install -Dm755 ${prometheusService} /etc/init.d/lumo-prometheus
    install -Dm755 ${grafanaService} /etc/init.d/lumo-grafana

    for service in \
      lumo-node-exporter \
      lumo-blackbox-exporter \
      lumo-prometheus \
      lumo-grafana; do
      /sbin/rc-update add "$service" default
      /sbin/rc-service "$service" restart
    done
  '';
}
