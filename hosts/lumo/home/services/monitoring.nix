{
  lab,
  lib,
  pkgs,
  ...
}:

let
  blackboxPort = 19115;
  nodeExporterPort = 19100;
  blockyScrapeInterval = "60s";

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
            targets = [ "127.0.0.1:${toString lab.ports.prometheus}" ];
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
        ];
      }
      {
        job_name = "traefik";
        static_configs = [
          {
            targets = [
              "127.0.0.1:${toString lab.ports.traefikMetrics}"
            ];
            labels.instance = "lumo";
          }
        ];
      }
      {
        job_name = "blocky";
        scrape_interval = blockyScrapeInterval;
        metrics_path = "/metrics";
        static_configs = [
          {
            targets = [ "127.0.0.1:4000" ];
            labels.instance = "lumo";
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
              "http://127.0.0.1:${toString lab.ports.cliproxyapi}/healthz"
            ];
            labels = {
              instance = "lumo";
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
    ];
  };

  prometheusService = pkgs.writeText "lumo-prometheus" ''
    #!/sbin/openrc-run
    name="lumo-prometheus"
    description="Lumo Prometheus"
    supervisor=supervise-daemon
    command="${pkgs.prometheus}/bin/prometheus"
    command_args="--config.file=${prometheusConfig} --storage.tsdb.path=/var/lib/prometheus --storage.tsdb.retention.time=30d --web.listen-address=127.0.0.1:${toString lab.ports.prometheus}"
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

in
{
  home.packages = [
    pkgs.prometheus
    pkgs.prometheus-blackbox-exporter
    pkgs.prometheus-node-exporter
  ];

  home.activation.lumoMonitoring = lib.hm.dag.entryAfter [ "lumoDirectories" "lumoBlocky" ] ''
    for account in prometheus; do
      if ! /usr/bin/getent group "$account" >/dev/null; then
        /usr/sbin/addgroup -S "$account"
      fi
      if ! /usr/bin/id "$account" >/dev/null 2>&1; then
        /usr/sbin/adduser -S -D -H -h "/var/lib/$account" -s /sbin/nologin -G "$account" "$account"
      fi
    done

    install -Dm755 ${nodeExporterService} /etc/init.d/lumo-node-exporter
    install -Dm755 ${blackboxService} /etc/init.d/lumo-blackbox-exporter
    install -Dm755 ${prometheusService} /etc/init.d/lumo-prometheus

    for service in \
      lumo-node-exporter \
      lumo-blackbox-exporter \
      lumo-prometheus; do
      /sbin/rc-update add "$service" default
      /sbin/rc-service "$service" restart
    done
  '';
}
