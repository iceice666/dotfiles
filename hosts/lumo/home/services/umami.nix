{
  config,
  dotfiles,
  homolab,
  lib,
  pkgs,
  ...
}:

let
  dataDir = "/var/lib/umami";
  envPath = "${dataDir}/umami.env";
  postgresPort = 15432;
  postgresImage = "docker.io/library/postgres:16-alpine";
  # Preserve Umami 3.2.0 and its dependencies; replace only the Node executable.
  # Both pinned images are linux/arm64 Alpine 3.24 builds.
  umamiContainerfile = ''
    FROM docker.io/library/node:22.23.4-alpine@sha256:fd4a97c1630a4a0a70117dd7b393e322db316d0489bdf36a0e776e7b235341b0 AS patched-node
    FROM ghcr.io/umami-software/umami@sha256:41c5df65ee777b762411c105f9b040e33708ef8640a19a2d2b9abf3284ee3f37
    COPY --from=patched-node /usr/local/bin/node /usr/local/bin/node
    ENV NODE_VERSION=22.23.4
    RUN test "$(node --version)" = v22.23.4
  '';
  umamiBuildContext = pkgs.writeTextDir "Containerfile" umamiContainerfile;
  umamiImage = "localhost/lumo-umami:node-${
    builtins.substring 0 16 (builtins.hashString "sha256" umamiContainerfile)
  }";
  ensureUmamiImage = pkgs.writeShellScript "lumo-umami-ensure-image" ''
    set -eu
    if ! ${pkgs.podman}/bin/podman image exists ${umamiImage}; then
      ${pkgs.podman}/bin/podman build --pull=missing --network=none \
        --file ${umamiBuildContext}/Containerfile --tag ${umamiImage} ${umamiBuildContext} >&2
    fi
  '';
  umamiPort = homolab.ports.umami;
  postgresPasswordPath = config.sops.secrets.umami-postgres-password.path;
  appSecretPath = config.sops.secrets.umami-app-secret.path;

  postgresService = pkgs.writeText "lumo-umami-postgres" ''
    #!/sbin/openrc-run
    name="lumo-umami-postgres"
    description="Lumo Umami PostgreSQL container"
    supervisor=supervise-daemon
    command="${pkgs.podman}/bin/podman"
    command_args="run --replace --rm --name=lumo-umami-postgres --network=host --env=POSTGRES_DB=umami --env=POSTGRES_USER=umami --env-file=/run/lumo-umami-postgres.env -v ${dataDir}/postgres:/var/lib/postgresql/data ${postgresImage} postgres -c listen_addresses=127.0.0.1 -c port=${toString postgresPort}"
    command_user="root"
    output_log="/var/log/lumo/umami-postgres.log"
    error_log="/var/log/lumo/umami-postgres.log"
    respawn_delay=5
    respawn_max=0

    depend() {
      need lumo-podman
      after networking
    }

    start_pre() {
      checkpath -f -m 0640 -o root:root /var/log/lumo/umami-postgres.log
      checkpath -d -m 0700 -o root:root ${dataDir}/postgres
      printf 'POSTGRES_PASSWORD=%s\n' "$(cat '${postgresPasswordPath}')" > /run/lumo-umami-postgres.env
      chmod 0400 /run/lumo-umami-postgres.env
      if ! ${pkgs.podman}/bin/podman image exists ${postgresImage}; then
        ${pkgs.podman}/bin/podman pull ${postgresImage} >&2
      fi
    }
  '';

  appService = pkgs.writeText "lumo-umami" ''
    #!/sbin/openrc-run
    name="lumo-umami"
    description="Lumo Umami analytics"
    supervisor=supervise-daemon
    command="${pkgs.podman}/bin/podman"
    command_args="run --replace --rm --name=lumo-umami --network=host --env-file=${envPath} --env=NODE_OPTIONS=--use-openssl-ca --env=SSL_CERT_FILE=/etc/dotfiles-ca.crt --env=SSL_CERT_DIR=/etc/dotfiles-certs --volume=${pkgs.dotfiles-cacert}/etc/ssl/certs/ca-no-trust-rules-bundle.crt:/etc/dotfiles-ca.crt:ro --volume=${pkgs.dotfiles-cacert.hashed}/etc/ssl/certs:/etc/dotfiles-certs:ro ${umamiImage}"
    command_user="root"
    output_log="/var/log/lumo/umami.log"
    error_log="/var/log/lumo/umami.log"
    respawn_delay=10
    respawn_max=0

    depend() {
      need lumo-podman lumo-umami-postgres
      after networking
    }

    start_pre() {
      checkpath -f -m 0640 -o root:root /var/log/lumo/umami.log
      ${ensureUmamiImage} || return $?
    }
  '';
in
{
  home.packages = [ pkgs.podman ];

  sops.secrets.umami-postgres-password = {
    sopsFile = dotfiles + /sensitive/hosts/lumo/umami.yaml;
    key = "postgresPassword";
    mode = "0400";
  };
  sops.secrets.umami-app-secret = {
    sopsFile = dotfiles + /sensitive/hosts/lumo/umami.yaml;
    key = "appSecret";
    mode = "0400";
  };

  home.activation.lumoUmami = lib.hm.dag.entryAfter [ "lumoDirectories" "sopsAlpine" "lumoPodman" ] ''
    # Fail before touching either running service if the derivative cannot be built.
    ${ensureUmamiImage} || exit $?

    install -d -m 0755 /var/log/lumo
    install -d -m 0700 -o root -g root ${dataDir}

    pg_pass="$(cat '${postgresPasswordPath}')"
    app_secret="$(cat '${appSecretPath}')"
    {
      printf 'DATABASE_URL=postgresql://umami:%s@127.0.0.1:${toString postgresPort}/umami\n' "$pg_pass"
      printf 'APP_SECRET=%s\n' "$app_secret"
      printf 'HOSTNAME=127.0.0.1\n'
      printf 'PORT=${toString umamiPort}\n'
      printf 'DISABLE_TELEMETRY=1\n'
    } > ${envPath}
    chmod 0400 ${envPath}

    install -Dm755 ${postgresService} /etc/init.d/lumo-umami-postgres
    install -Dm755 ${appService} /etc/init.d/lumo-umami
    /sbin/rc-update add lumo-umami-postgres default
    /sbin/rc-update add lumo-umami default
    restart_service() {
      service="$1"
      if ! /sbin/rc-service "$service" restart; then
        sleep 5
        /sbin/rc-service "$service" restart
      fi
    }

    restart_service lumo-umami-postgres
    sleep 5
    restart_service lumo-umami
  '';
}
