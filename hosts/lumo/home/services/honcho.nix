{
  config,
  dotfiles,
  homolab,
  lib,
  pkgs,
  ...
}:

let
  dataDir = "/var/lib/honcho";
  envPath = "/run/lumo-honcho/env";
  network = "lumo-honcho";
  image = "localhost/honcho:e8ef1a06e53bc3f69c3f2c7621cfe9abf66839bc";

  honchoSource = pkgs.fetchFromGitHub {
    owner = "plastic-labs";
    repo = "honcho";
    rev = "e8ef1a06e53bc3f69c3f2c7621cfe9abf66839bc";
    hash = "sha256-Hez2jckDQJ0f81DNWFG1aStsQFRSfexeW6ZGKbo9CA8=";
  };

  cliproxyapiBaseUrl = "http://host.containers.internal:${toString homolab.ports.cliproxyapi}/v1";
  honchoPort = homolab.ports.honcho;
  sharedApiKeyPath = config.sops.secrets.cliproxyapi-shared-api-key.path;

  ensureImage = ''
    if ! ${pkgs.podman}/bin/podman image exists ${image}; then
      ${pkgs.podman}/bin/podman build --network=host -t ${image} ${honchoSource} >&2
    fi
  '';

  ensureNetwork = ''
    if ! ${pkgs.podman}/bin/podman network exists ${network}; then
      ${pkgs.podman}/bin/podman network create ${network} >&2
    fi
  '';

  postgresService = pkgs.writeText "lumo-honcho-postgres" ''
    #!/sbin/openrc-run
    name="lumo-honcho-postgres"
    description="Lumo Honcho PostgreSQL/pgvector container"
    supervisor=supervise-daemon
    command="${pkgs.podman}/bin/podman"
    command_args="run --replace --rm --name=lumo-honcho-postgres --network=${network} --env=POSTGRES_DB=postgres --env=POSTGRES_USER=postgres --env=POSTGRES_PASSWORD=postgres --env=PGDATA=/var/lib/postgresql/data/pgdata -v ${dataDir}/postgres:/var/lib/postgresql/data -v ${honchoSource}/database/init.sql:/docker-entrypoint-initdb.d/init.sql:ro docker.io/pgvector/pgvector:pg15 postgres -c max_connections=200"
    command_user="root"
    output_log="/var/log/lumo/honcho-postgres.log"
    error_log="/var/log/lumo/honcho-postgres.log"
    respawn_delay=5
    respawn_max=0

    depend() {
      need lumo-podman
      after networking
    }

    start_pre() {
      checkpath -f -m 0640 -o root:root /var/log/lumo/honcho-postgres.log
      checkpath -d -m 0700 -o root:root ${dataDir}/postgres
      ${ensureNetwork}
      if ! ${pkgs.podman}/bin/podman image exists docker.io/pgvector/pgvector:pg15; then
        ${pkgs.podman}/bin/podman pull docker.io/pgvector/pgvector:pg15 >&2
      fi
    }
  '';

  redisService = pkgs.writeText "lumo-honcho-redis" ''
    #!/sbin/openrc-run
    name="lumo-honcho-redis"
    description="Lumo Honcho Redis container"
    supervisor=supervise-daemon
    command="${pkgs.podman}/bin/podman"
    command_args="run --replace --rm --name=lumo-honcho-redis --network=${network} -v ${dataDir}/redis:/data docker.io/library/redis:8.2"
    command_user="root"
    output_log="/var/log/lumo/honcho-redis.log"
    error_log="/var/log/lumo/honcho-redis.log"
    respawn_delay=5
    respawn_max=0

    depend() {
      need lumo-podman
      after networking
    }

    start_pre() {
      checkpath -f -m 0640 -o root:root /var/log/lumo/honcho-redis.log
      checkpath -d -m 0700 -o root:root ${dataDir}/redis
      ${ensureNetwork}
      if ! ${pkgs.podman}/bin/podman image exists docker.io/library/redis:8.2; then
        ${pkgs.podman}/bin/podman pull docker.io/library/redis:8.2 >&2
      fi
    }
  '';

  apiService = pkgs.writeText "lumo-honcho-api" ''
    #!/sbin/openrc-run
    name="lumo-honcho-api"
    description="Lumo Honcho API container"
    supervisor=supervise-daemon
    command="${pkgs.podman}/bin/podman"
    command_args="run --replace --rm --name=lumo-honcho-api --network=${network} -p 127.0.0.1:${toString honchoPort}:8000 --env-file=${envPath} ${image} sh docker/entrypoint.sh"
    command_user="root"
    output_log="/var/log/lumo/honcho-api.log"
    error_log="/var/log/lumo/honcho-api.log"
    respawn_delay=10
    respawn_max=0

    depend() {
      need lumo-podman lumo-honcho-postgres lumo-honcho-redis lumo-cliproxyapi
      after networking
    }

    start_pre() {
      checkpath -f -m 0640 -o root:root /var/log/lumo/honcho-api.log
      ${ensureNetwork}
      ${ensureImage}
    }
  '';

  deriverService = pkgs.writeText "lumo-honcho-deriver" ''
    #!/sbin/openrc-run
    name="lumo-honcho-deriver"
    description="Lumo Honcho deriver worker container"
    supervisor=supervise-daemon
    command="${pkgs.podman}/bin/podman"
    command_args="run --replace --rm --name=lumo-honcho-deriver --network=${network} --env-file=${envPath} ${image} /app/.venv/bin/python -m src.deriver"
    command_user="root"
    output_log="/var/log/lumo/honcho-deriver.log"
    error_log="/var/log/lumo/honcho-deriver.log"
    respawn_delay=10
    respawn_max=0

    depend() {
      need lumo-podman lumo-honcho-api
      after networking
    }

    start_pre() {
      checkpath -f -m 0640 -o root:root /var/log/lumo/honcho-deriver.log
      ${ensureNetwork}
      ${ensureImage}
    }
  '';
in
{
  home.packages = [ pkgs.podman ];

  sops.secrets.cliproxyapi-shared-api-key = {
    sopsFile = dotfiles + /sensitive/shared/cliproxyapi.yaml;
    key = "apiKey";
    mode = "0400";
  };

  home.activation.lumoHoncho =
    lib.hm.dag.entryAfter [ "lumoDirectories" "sopsAlpine" "lumoPodman" ]
      ''
            install -d -m 0755 /var/log/lumo
            install -d -m 0700 -o root -g root ${dataDir} /run/lumo-honcho

            shared_api_key="$(cat '${sharedApiKeyPath}')"
            cat > ${envPath} << EOF
        LOG_LEVEL=INFO
        AUTH_USE_AUTH=false
        DB_CONNECTION_URI=postgresql+psycopg://postgres:postgres@lumo-honcho-postgres:5432/postgres
        CACHE_ENABLED=true
        CACHE_URL=redis://lumo-honcho-redis:6379/0?suppress=true
        LLM_OPENAI_API_KEY=$shared_api_key
        DERIVER_MODEL_CONFIG__MODEL=gpt-5.5
        DERIVER_MODEL_CONFIG__OVERRIDES__BASE_URL=${cliproxyapiBaseUrl}
        DIALECTIC_LEVELS__minimal__MODEL_CONFIG__MODEL=gpt-5.5
        DIALECTIC_LEVELS__minimal__MODEL_CONFIG__OVERRIDES__BASE_URL=${cliproxyapiBaseUrl}
        DIALECTIC_LEVELS__low__MODEL_CONFIG__MODEL=gpt-5.5
        DIALECTIC_LEVELS__low__MODEL_CONFIG__OVERRIDES__BASE_URL=${cliproxyapiBaseUrl}
        DIALECTIC_LEVELS__medium__MODEL_CONFIG__MODEL=gpt-5.5
        DIALECTIC_LEVELS__medium__MODEL_CONFIG__OVERRIDES__BASE_URL=${cliproxyapiBaseUrl}
        DIALECTIC_LEVELS__high__MODEL_CONFIG__MODEL=gpt-5.5
        DIALECTIC_LEVELS__high__MODEL_CONFIG__OVERRIDES__BASE_URL=${cliproxyapiBaseUrl}
        DIALECTIC_LEVELS__max__MODEL_CONFIG__MODEL=gpt-5.5
        DIALECTIC_LEVELS__max__MODEL_CONFIG__OVERRIDES__BASE_URL=${cliproxyapiBaseUrl}
        SUMMARY_MODEL_CONFIG__MODEL=gpt-5.5
        SUMMARY_MODEL_CONFIG__OVERRIDES__BASE_URL=${cliproxyapiBaseUrl}
        DREAM_DEDUCTION_MODEL_CONFIG__MODEL=gpt-5.5
        DREAM_DEDUCTION_MODEL_CONFIG__OVERRIDES__BASE_URL=${cliproxyapiBaseUrl}
        DREAM_INDUCTION_MODEL_CONFIG__MODEL=gpt-5.5
        DREAM_INDUCTION_MODEL_CONFIG__OVERRIDES__BASE_URL=${cliproxyapiBaseUrl}
        EMBEDDING_MODEL_CONFIG__MODEL=text-embedding-3-small
        EMBEDDING_MODEL_CONFIG__OVERRIDES__BASE_URL=${cliproxyapiBaseUrl}
        EOF
            chmod 0400 ${envPath}

            install -d -m 0755 /etc/containers
            if [ ! -f /etc/containers/policy.json ]; then
              cat > /etc/containers/policy.json << 'POLICYEOF'
        {"default":[{"type":"insecureAcceptAnything"}]}
        POLICYEOF
              chmod 0644 /etc/containers/policy.json
            fi

            install -Dm755 ${postgresService} /etc/init.d/lumo-honcho-postgres
            install -Dm755 ${redisService} /etc/init.d/lumo-honcho-redis
            install -Dm755 ${apiService} /etc/init.d/lumo-honcho-api
            install -Dm755 ${deriverService} /etc/init.d/lumo-honcho-deriver
            /sbin/rc-update add lumo-honcho-postgres default
            /sbin/rc-update add lumo-honcho-redis default
            /sbin/rc-update add lumo-honcho-api default
            /sbin/rc-update add lumo-honcho-deriver default
            /sbin/rc-service lumo-honcho-postgres restart
            /sbin/rc-service lumo-honcho-redis restart
            /sbin/rc-service lumo-honcho-api restart
            /sbin/rc-service lumo-honcho-deriver restart
      '';
}
