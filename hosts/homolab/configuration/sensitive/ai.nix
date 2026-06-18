{
  config,
  dotfiles,
  homolab,
  ...
}:

{
  sops = {
    secrets = {
      # valkey-requirepass moved to lumo's root Home Manager service configuration.

      "cliproxyapi-api-key" = {
        sopsFile = dotfiles + /sensitive/hosts/homolab/cliproxyapi.yaml;
        key = "apiKey";
        owner = "root";
        group = "root";
        mode = "0400";
        restartUnits = [ "cliproxyapi.service" ];
      };

      "cliproxyapi-management-key" = {
        sopsFile = dotfiles + /sensitive/hosts/homolab/cliproxyapi.yaml;
        key = "managementKey";
        owner = "root";
        group = "root";
        mode = "0400";
        restartUnits = [ "cliproxyapi.service" ];
      };
    };

    templates = {
      "cliproxyapi-config.yaml" = {
        content = ''
          host: "0.0.0.0"
          port: ${toString homolab.ports.cliproxyapi}

          remote-management:
            allow-remote: true
            secret-key: "${config.sops.placeholder."cliproxyapi-management-key"}"
            disable-control-panel: false
            disable-auto-update-panel: true

          auth-dir: "/mnt/storage/cliproxyapi/auths"

          api-keys:
            - "${config.sops.placeholder."cliproxyapi-api-key"}"

          debug: false

          pprof:
            enable: false
            addr: "127.0.0.1:8316"

          plugins:
            enabled: false
            dir: "/mnt/storage/cliproxyapi/plugins"
            configs: {}

          commercial-mode: false
          logging-to-file: false
          logs-max-total-size-mb: 0
          error-logs-max-files: 10
          usage-statistics-enabled: true
          redis-usage-queue-retention-seconds: 3600
          proxy-url: ""
          force-model-prefix: false
          passthrough-headers: false
          request-retry: 3
          max-retry-credentials: 0
          max-retry-interval: 30
          disable-cooling: false
        '';
        owner = "cliproxyapi";
        group = "cliproxyapi";
        mode = "0400";
      };
    };
  };
}
