{
  config,
  dotfiles,
  homolab,
  lib,
  pkgs,
  ...
}:

let
  dataDir = "/var/lib/cliproxyapi";
  configPath = "/var/lib/cliproxyapi/config.yaml";
  port = homolab.ports.cliproxyapi;

  homonetApiKeyPath = config.sops.secrets.cliproxyapi-homonet-api-key.path;
  managementKeyPath = config.sops.secrets.cliproxyapi-management-key.path;
  sharedApiKeyPath = config.sops.secrets.cliproxyapi-shared-api-key.path;

  # CLIProxyAPI is a prebuilt glibc binary; lumo is Alpine (musl).
  # Run through the Nix glibc loader so shared libraries resolve.
  cliproxyapiWrapper = pkgs.writeShellScript "cli-proxy-api-wrapper" ''
    export LD_LIBRARY_PATH="${pkgs.glibc}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    exec ${pkgs.glibc}/lib/ld-linux-aarch64.so.1 ${pkgs.cliproxyapi-bin}/bin/cli-proxy-api "$@"
  '';

  cliproxyapiService = pkgs.writeText "lumo-cliproxyapi" ''
    #!/sbin/openrc-run
    name="lumo-cliproxyapi"
    description="Lumo CLIProxyAPI OpenAI-compatible CLI proxy"
    supervisor=supervise-daemon
    command="${cliproxyapiWrapper}"
    command_args="-config ${configPath}"
    command_user="cliproxyapi:cliproxyapi"
    directory="${dataDir}"
    output_log="/var/log/lumo/cliproxyapi.log"
    error_log="/var/log/lumo/cliproxyapi.log"
    respawn_delay=5
    respawn_max=0

    depend() {
      need net
    }

    start_pre() {
      checkpath -f -m 0640 -o cliproxyapi:cliproxyapi /var/log/lumo/cliproxyapi.log
      checkpath -d -m 0750 -o cliproxyapi:cliproxyapi ${dataDir}
      checkpath -d -m 0750 -o cliproxyapi:cliproxyapi ${dataDir}/auths
      checkpath -d -m 0750 -o cliproxyapi:cliproxyapi ${dataDir}/plugins
    }
  '';
in
{
  sops.secrets.cliproxyapi-homonet-api-key = {
    sopsFile = dotfiles + /sensitive/hosts/lumo/cliproxyapi.yaml;
    key = "homonetApiKey";
    mode = "0400";
  };

  sops.secrets.cliproxyapi-management-key = {
    sopsFile = dotfiles + /sensitive/hosts/lumo/cliproxyapi.yaml;
    key = "managementKey";
    mode = "0400";
  };

  sops.secrets.cliproxyapi-shared-api-key = {
    sopsFile = dotfiles + /sensitive/shared/cliproxyapi.yaml;
    key = "apiKey";
    mode = "0400";
  };

  home.activation.lumoCliproxyapi = lib.hm.dag.entryAfter [ "lumoDirectories" "sopsAlpine" ] ''
        if ! /usr/bin/getent group cliproxyapi >/dev/null; then
          /usr/sbin/addgroup -S cliproxyapi
        fi
        if ! /usr/bin/id cliproxyapi >/dev/null 2>&1; then
          /usr/sbin/adduser -S -D -H -h ${dataDir} -s /sbin/nologin -G cliproxyapi cliproxyapi
        fi

        install -d -m 0750 -o cliproxyapi -g cliproxyapi ${dataDir}
        install -d -m 0750 -o cliproxyapi -g cliproxyapi ${dataDir}/auths
        install -d -m 0750 -o cliproxyapi -g cliproxyapi ${dataDir}/plugins

        homonet_api_key="$(cat '${homonetApiKeyPath}')"
        management_key="$(cat '${managementKeyPath}')"
        shared_api_key="$(cat '${sharedApiKeyPath}')"

        cat > ${configPath} << EOF
    host: "0.0.0.0"
    port: ${toString port}

    remote-management:
      allow-remote: true
      secret-key: "$management_key"
      disable-control-panel: false
      disable-auto-update-panel: true

    auth-dir: "${dataDir}/auths"

    api-keys:
      - $homonet_api_key
      - $shared_api_key

    debug: false

    pprof:
      enable: false
      addr: "127.0.0.1:8316"

    plugins:
      enabled: false
      dir: "${dataDir}/plugins"
      configs: {}

    commercial-mode: false
    logging-to-file: true
    logs-max-total-size-mb: 0
    error-logs-max-files: 10
    usage-statistics-enabled: true
    redis-usage-queue-retention-seconds: 3600
    proxy-url: ""
    force-model-prefix: false
    passthrough-headers: false
    streaming:
      keepalive-seconds: 10
      bootstrap-retries: 2
    request-retry: 5
    max-retry-credentials: 0
    max-retry-interval: 60
    disable-cooling: false
    quota-exceeded:
      switch-project: true
      switch-preview-model: true
      antigravity-credits: true
    oauth-excluded-models:
      claude:
        - "claude-3-5-haiku-20241022"
        - "claude-3-7-sonnet-20250219"
        - "claude-fable-5"
        - "claude-opus-4-1-20250805"
        - "claude-opus-4-20250514"
        - "claude-opus-4-5-20251101"
        - "claude-opus-4-6"
        - "claude-opus-4-7"
        - "claude-sonnet-4-20250514"
        - "claude-sonnet-4-5-20250929"
      codex:
        - "gpt-5.4"
        - "gpt-image-1.5"
    EOF

        chown cliproxyapi:cliproxyapi ${configPath}
        chmod 0400 ${configPath}

        install -Dm755 ${cliproxyapiService} /etc/init.d/lumo-cliproxyapi
        /sbin/rc-update add lumo-cliproxyapi default
        # --nodeps: do not stop the honcho/hermes services that `need
        # lumo-cliproxyapi`. They reconnect on the next request and are
        # restarted by their own steps; cascading races the OpenRC lock.
        /sbin/rc-service --nodeps lumo-cliproxyapi restart
  '';
}
