{
  config,
  homolab,
  pkgs,
  ...
}:

let
  blackboxPort = 19115;
  blackboxTarget = "127.0.0.1:${toString blackboxPort}";
  llamaSwapProbeTargets = [
    "${homolab.ai.baseUrl}/health"
    "${homolab.ai.openaiBaseUrl}/models"
  ];
in

{
  services.prometheus = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = homolab.ports.prometheus;
    retentionTime = "30d";

    globalConfig = {
      scrape_interval = "15s";
      evaluation_interval = "15s";
    };

    exporters.blackbox = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = blackboxPort;
      configFile = pkgs.writeText "blackbox.yml" (
        builtins.toJSON {
          modules.http_2xx = {
            prober = "http";
            timeout = "10s";
            http = {
              method = "GET";
              preferred_ip_protocol = "ip4";
              valid_status_codes = [ 200 ];
            };
          };
        }
      );
    };

    scrapeConfigs = [
      {
        job_name = "prometheus";
        static_configs = [
          {
            targets = [ "127.0.0.1:${toString homolab.ports.prometheus}" ];
            labels.instance = homolab.hostName;
          }
        ];
      }
      {
        job_name = "traefik";
        static_configs = [
          {
            targets = [ "127.0.0.1:${toString homolab.ports.traefikMetrics}" ];
            labels.instance = homolab.hostName;
          }
        ];
      }
      {
        job_name = "llama-swap-blackbox";
        metrics_path = "/probe";
        params.module = [ "http_2xx" ];
        static_configs = [
          {
            targets = llamaSwapProbeTargets;
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
            replacement = blackboxTarget;
          }
        ];
      }
    ];

    rules = [
      ''
        groups:
          - name: llama-swap.rules
            rules:
              - alert: LlamaSwapEndpointDown
                expr: probe_success{job="llama-swap-blackbox", service="llama-swap"} == 0
                for: 2m
                labels:
                  severity: warning
                  service: llama-swap
                annotations:
                  summary: "llama-swap endpoint probe failed"
                  description: "{{ $labels.target }} has failed HTTP probing for more than 2 minutes."
              - alert: LlamaSwapProbeSlow
                expr: probe_duration_seconds{job="llama-swap-blackbox", service="llama-swap"} > 5
                for: 5m
                labels:
                  severity: warning
                  service: llama-swap
                annotations:
                  summary: "llama-swap endpoint probe is slow"
                  description: "{{ $labels.target }} has taken more than 5 seconds to answer for 5 minutes."
      ''
    ];
  };

  services.grafana = {
    enable = true;

    settings = {
      analytics = {
        reporting_enabled = false;
        check_for_updates = false;
        check_for_plugin_updates = false;
      };

      server = {
        http_addr = "127.0.0.1";
        http_port = homolab.ports.grafana;
        domain = homolab.domains.grafana;
        enforce_domain = true;
        root_url = "${homolab.urls.grafana}/";
      };

      security = {
        disable_initial_admin_creation = true;
        secret_key = "$__file{${config.sops.secrets."grafana-secret-key".path}}";
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
        whitelist = "127.0.0.1";
        headers = "Name:Remote-Name Email:Remote-Email Groups:Remote-Groups";
      };
    };

    provision = {
      datasources.settings = {
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
        ];
      };

      dashboards.settings = {
        apiVersion = 1;
        providers = [
          {
            name = "homolab";
            type = "file";
            folder = "Homolab";
            editable = true;
            allowUiUpdates = true;
            options.path = ./grafana-dashboards;
          }
        ];
      };
    };
  };
}
