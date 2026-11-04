{
  config,
  dotfiles,
  lab,
  lib,
  pkgs,
  ...
}:

let
  dataDir = "/var/lib/umami";
  envPath = "${dataDir}/umami.env";
  # Umami lives in lumo's host PostgreSQL (database.nix), reached over
  # loopback TCP with SCRAM because the container cannot use peer auth.
  postgresPort = lab.ports.postgresql;
  postgresClient = pkgs.postgresql_17;
  asPostgres = "${pkgs.util-linux}/bin/runuser -u postgres --";
  hostPsql = "${asPostgres} ${postgresClient}/bin/psql -X -q -h /run/postgresql -p ${toString postgresPort} -v ON_ERROR_STOP=1";

  # One-time migration source: the former dedicated PostgreSQL 16 container.
  # Its data directory is kept for rollback. Remove this block, the legacy
  # image and `${dataDir}/postgres` once the host database is confirmed.
  legacyPostgresImage = "docker.io/library/postgres:16-alpine@sha256:0cefaabd882e42bcb2a2f3dc56d3ce4770560ba62fd7f197f1a2e008fd5731ab";
  legacyDataDir = "${dataDir}/postgres";
  migratedMarker = "${dataDir}/host-postgres";
  migrateLegacy = pkgs.writeShellScript "lumo-umami-migrate-host-postgres" ''
    set -euo pipefail
    cd /
    podman=${pkgs.podman}/bin/podman
    if [ -f ${migratedMarker} ] || [ ! -s ${legacyDataDir}/PG_VERSION ]; then
      exit 0
    fi
    # Freeze writes; the service sweep may already have stopped both.
    /sbin/rc-service lumo-umami stop 2>/dev/null || true
    /sbin/rc-service lumo-umami-postgres stop 2>/dev/null || true
    $podman rm -f lumo-umami lumo-umami-postgres lumo-umami-migrate >/dev/null 2>&1 || true

    if ! $podman image exists ${legacyPostgresImage}; then
      $podman pull ${legacyPostgresImage} >&2
    fi
    $podman run -d --rm --name=lumo-umami-migrate --network=none \
      -v ${legacyDataDir}:/var/lib/postgresql/data ${legacyPostgresImage} >/dev/null
    trap '$podman stop -t 10 lumo-umami-migrate >/dev/null 2>&1 || true' EXIT
    ready=0
    for _ in $(seq 1 30); do
      if $podman exec lumo-umami-migrate pg_isready -U umami -d umami >/dev/null 2>&1; then
        ready=1
        break
      fi
      sleep 1
    done
    [ "$ready" = 1 ] || { echo "umami: legacy postgres did not become ready" >&2; exit 1; }

    install -d -m 0700 -o root -g root ${backupDir}
    dump="${backupDir}/migrate-host-postgres-$(date -u +%Y%m%dT%H%M%SZ).sql.gz"
    $podman exec lumo-umami-migrate pg_dump -U umami umami | ${pkgs.gzip}/bin/gzip > "$dump"
    chmod 0600 "$dump"
    if [ "$(${pkgs.gzip}/bin/gzip -cd "$dump" | head -c 64 | wc -c)" -eq 0 ]; then
      echo "umami: migration dump is empty; refusing to continue" >&2
      exit 1
    fi

    # No marker means Umami never ran against the host database, so a
    # leftover copy from an interrupted attempt can be discarded.
    ${hostPsql} -d postgres -c 'DROP DATABASE IF EXISTS umami WITH (FORCE)' -c 'CREATE DATABASE umami OWNER umami'
    ${pkgs.gzip}/bin/gzip -cd "$dump" | ${hostPsql} -d umami --single-transaction -f - >/dev/null

    counts="select (select count(*) from website_event) || ':' || (select count(*) from session) || ':' || (select count(*) from website) || ':' || (select count(*) from \"user\")"
    old="$($podman exec lumo-umami-migrate psql -X -At -U umami -d umami -c "$counts")"
    new="$(${hostPsql} -At -d umami -c "$counts")"
    if [ "$old" != "$new" ]; then
      echo "umami: row counts differ after migration (legacy $old, host $new)" >&2
      exit 1
    fi
    printf 'migrated %s from %s (%s)\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$dump" "$new" > ${migratedMarker}
    chmod 0600 ${migratedMarker}
    echo "umami: migrated to host postgres (events:sessions:websites:users = $new)" >&2
  '';

  # Idempotent role/database provisioning; the password comes from the
  # environment so it never appears on a command line.
  ensureHostDatabase = pkgs.writeShellScript "lumo-umami-ensure-host-database" ''
    set -euo pipefail
    cd /
    for _ in $(seq 1 30); do
      ${asPostgres} ${postgresClient}/bin/pg_isready -q -h /run/postgresql -p ${toString postgresPort} && break
      sleep 1
    done
    UMAMI_DB_PASSWORD="$(cat '${postgresPasswordPath}')"
    export UMAMI_DB_PASSWORD
    ${hostPsql} -d postgres <<'SQL'
    SELECT 'CREATE ROLE umami LOGIN' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'umami') \gexec
    \getenv pw UMAMI_DB_PASSWORD
    ALTER ROLE umami WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD :'pw';
    SQL
  '';

  # Fresh hosts (no legacy data) get an empty database owned by umami.
  ensureEmptyDatabase = pkgs.writeShellScript "lumo-umami-ensure-empty-database" ''
    set -euo pipefail
    cd /
    ${hostPsql} -d postgres <<'SQL'
    SELECT 'CREATE DATABASE umami OWNER umami' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'umami') \gexec
    SQL
  '';
  # Upstream 3.4.1 (security hotfix: Next.js 16.4.2) already ships Node
  # 22.23.4 on Alpine 3.24.3, so the former Node-replacement Containerfile is
  # no longer needed. Digest-pinned linux/arm64 manifest list.
  umamiImage = "ghcr.io/umami-software/umami:3.4.1@sha256:e69d1a7932e9dab0fc523edc7be1f3a53f3c261f57856fc2167ae74a8fc022e8";
  ensureUmamiImage = pkgs.writeShellScript "lumo-umami-ensure-image" ''
    set -eu
    if ! ${pkgs.podman}/bin/podman image exists ${umamiImage}; then
      ${pkgs.podman}/bin/podman pull ${umamiImage} >&2
    fi
  '';
  # Umami runs Prisma migrations on startup. Dump the database before the
  # first start of a new image so a failed migration can be rolled back.
  imageMarker = "${dataDir}/image";
  backupDir = "${dataDir}/backups";
  preUpgradeBackup = pkgs.writeShellScript "lumo-umami-pre-upgrade-backup" ''
    set -euo pipefail
    if [ -f ${imageMarker} ] && [ "$(cat ${imageMarker})" = "${umamiImage}" ]; then
      exit 0
    fi
    cd /
    if [ "$(${hostPsql} -At -d postgres -c "select count(*) from pg_database where datname = 'umami'")" != 1 ]; then
      echo "umami: no host database yet; skipping pre-upgrade dump" >&2
      exit 0
    fi
    install -d -m 0700 -o root -g root ${backupDir}
    dump="${backupDir}/pre-upgrade-$(date -u +%Y%m%dT%H%M%SZ).sql.gz"
    ${asPostgres} ${postgresClient}/bin/pg_dump -h /run/postgresql -p ${toString postgresPort} umami \
      | ${pkgs.gzip}/bin/gzip > "$dump"
    chmod 0600 "$dump"
    if [ "$(${pkgs.gzip}/bin/gzip -cd "$dump" | head -c 64 | wc -c)" -eq 0 ]; then
      echo "umami: pre-upgrade dump is empty; refusing to continue" >&2
      exit 1
    fi
    echo "umami: pre-upgrade dump written to $dump" >&2
    # Keep the five newest dumps.
    ls -1t ${backupDir}/pre-upgrade-*.sql.gz 2>/dev/null | tail -n +6 | xargs -r rm -f
  '';
  umamiPort = lab.ports.umami;
  postgresPasswordPath = config.sops.secrets.umami-postgres-password.path;
  appSecretPath = config.sops.secrets.umami-app-secret.path;

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
      need lumo-podman lumo-postgresql
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

  home.activation.lumoUmami =
    lib.hm.dag.entryAfter
      [
        "lumoDirectories"
        "lumoDatabase"
        "sopsAlpine"
        "lumoPodman"
      ]
      ''
        install -d -m 0755 /var/log/lumo
        install -d -m 0700 -o root -g root ${dataDir}

        # Fail before touching the running service if the image cannot be pulled.
        ${ensureUmamiImage} || exit $?
        ${ensureHostDatabase} || exit $?
        ${migrateLegacy} || exit $?
        ${preUpgradeBackup} || exit $?
        ${ensureEmptyDatabase} || exit $?

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

        install -Dm755 ${appService} /etc/init.d/lumo-umami
        /sbin/rc-update add lumo-umami default
        restart_service() {
          service="$1"
          if ! /sbin/rc-service "$service" restart; then
            sleep 5
            /sbin/rc-service "$service" restart
          fi
        }

        restart_service lumo-umami
        printf '%s\n' '${umamiImage}' > ${imageMarker}
      '';
}
