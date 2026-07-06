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
  umamiImage = "ghcr.io/umami-software/umami:postgresql-latest";
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
    command_args="run --replace --rm --name=lumo-umami --network=host --env-file=${envPath} ${umamiImage}"
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
      if ! ${pkgs.podman}/bin/podman image exists ${umamiImage}; then
        ${pkgs.podman}/bin/podman pull ${umamiImage} >&2
      fi
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
    install -d -m 0755 /var/log/lumo
    install -d -m 0700 -o root -g root ${dataDir}

    pg_pass="$(cat '${postgresPasswordPath}')"
    app_secret="$(cat '${appSecretPath}')"
    {
      printf 'DATABASE_URL=postgresql://umami:%s@127.0.0.1:${toString postgresPort}/umami\n' "$pg_pass"
      printf 'APP_SECRET=%s\n' "$app_secret"
      printf 'HOSTNAME=0.0.0.0\n'
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
