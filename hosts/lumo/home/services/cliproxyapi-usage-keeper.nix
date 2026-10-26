{
  config,
  dotfiles,
  lab,
  lib,
  pkgs,
  ...
}:

let
  dataDir = "/var/lib/cliproxyapi-usage-keeper";
  envPath = "${dataDir}/keeper.env";
  # Digest-pinned so a re-tagged upstream release cannot change what runs.
  # v2 requires CPA 8.0.12+ (lumo runs 8.0.43). First v2 start migrates the
  # v1 database in place; a pre-upgrade copy is taken below in case rollback
  # to v1.15.11 is needed (never open a migrated database with v1).
  image = "ghcr.io/willxup/cpa-usage-keeper:v2.0.1@sha256:2f34d43cf3faf073078757290abd325c76a726d38d4d31688bc0640881e86a41";
  imageMarker = "${dataDir}/image";
  preUpgradeBackup = pkgs.writeShellScript "lumo-keeper-pre-upgrade-backup" ''
    set -eu
    if [ -f ${imageMarker} ] && [ "$(cat ${imageMarker})" = "${image}" ]; then
      exit 0
    fi
    if [ ! -f ${dataDir}/data/app.db ]; then
      exit 0
    fi
    dest="${dataDir}/pre-upgrade-$(date -u +%Y%m%dT%H%M%SZ)"
    install -d -m 0700 "$dest"
    # The container is stopped at this point, so the WAL can be copied as-is.
    cp -p ${dataDir}/data/app.db "$dest/"
    for f in ${dataDir}/data/app.db-wal ${dataDir}/data/app.db-shm; do
      [ -f "$f" ] && cp -p "$f" "$dest/"
    done
    echo "keeper: pre-upgrade database copied to $dest" >&2
    ls -1dt ${dataDir}/pre-upgrade-* | tail -n +4 | xargs -r rm -rf
  '';
  port = lab.ports.cliproxyapiUsageKeeper;

  managementKeyPath = config.sops.secrets.cliproxyapi-management-key.path;
  loginPasswordPath = config.sops.secrets.cliproxyapi-usage-keeper-login-password.path;

  keeperService = pkgs.writeText "lumo-cliproxyapi-usage-keeper" ''
    #!/sbin/openrc-run
    name="lumo-cliproxyapi-usage-keeper"
    description="Lumo CPA Usage Keeper analytics dashboard"
    supervisor=supervise-daemon
    command="${pkgs.podman}/bin/podman"
    command_args="run --replace --rm --name=lumo-cliproxyapi-usage-keeper --network=host --env-file=${envPath} --env=SSL_CERT_FILE=/etc/dotfiles-ca.crt --env=SSL_CERT_DIR=/etc/dotfiles-certs --volume=${pkgs.dotfiles-cacert}/etc/ssl/certs/ca-no-trust-rules-bundle.crt:/etc/dotfiles-ca.crt:ro --volume=${pkgs.dotfiles-cacert.hashed}/etc/ssl/certs:/etc/dotfiles-certs:ro -v ${dataDir}/data:/data ${image}"
    command_user="root"
    output_log="/var/log/lumo/cliproxyapi-usage-keeper.log"
    error_log="/var/log/lumo/cliproxyapi-usage-keeper.log"
    respawn_delay=10
    respawn_max=0

    depend() {
      need lumo-podman lumo-cliproxyapi
      after networking
    }

    start_pre() {
      checkpath -f -m 0640 -o root:root /var/log/lumo/cliproxyapi-usage-keeper.log
      checkpath -d -m 0700 -o root:root ${dataDir}
      checkpath -d -m 0750 -o root:root ${dataDir}/data
      if ! ${pkgs.podman}/bin/podman image exists ${image}; then
        ${pkgs.podman}/bin/podman pull ${image} >&2
      fi
    }
  '';
in
{
  home.packages = [ pkgs.podman ];

  sops.secrets.cliproxyapi-management-key = {
    sopsFile = dotfiles + /sensitive/hosts/lumo/cliproxyapi.yaml;
    key = "managementKey";
    mode = "0400";
  };

  sops.secrets.cliproxyapi-usage-keeper-login-password = {
    sopsFile = dotfiles + /sensitive/hosts/lumo/cliproxyapi.yaml;
    key = "keeperLoginPassword";
    mode = "0400";
  };

  home.activation.lumoCliproxyapiUsageKeeper =
    lib.hm.dag.entryAfter [ "lumoDirectories" "sopsAlpine" "lumoPodman" "lumoCliproxyapi" ]
      ''
        install -d -m 0700 -o root -g root ${dataDir}
        install -d -m 0750 -o root -g root ${dataDir}/data

        management_key="$(cat '${managementKeyPath}')"
        login_password="$(cat '${loginPasswordPath}')"
        {
          printf 'CPA_BASE_URL=http://127.0.0.1:${toString lab.ports.cliproxyapi}\n'
          printf 'CPA_MANAGEMENT_KEY=%s\n' "$management_key"
          printf 'REDIS_QUEUE_ADDR=127.0.0.1:${toString lab.ports.cliproxyapi}\n'
          printf 'APP_HOST=127.0.0.1\n'
          printf 'APP_PORT=${toString port}\n'
          printf 'APP_BASE_PATH=/keeper\n'
          printf 'AUTH_ENABLED=true\n'
          printf 'LOGIN_PASSWORD=%s\n' "$login_password"
          printf 'TZ=Asia/Taipei\n'
          printf 'WORK_DIR=/data\n'
          printf 'TRUSTED_PROXY_CIDRS=127.0.0.1/32\n'
        } > ${envPath}
        chmod 0400 ${envPath}

        install -Dm755 ${keeperService} /etc/init.d/lumo-cliproxyapi-usage-keeper
        /sbin/rc-update add lumo-cliproxyapi-usage-keeper default
        /sbin/rc-service lumo-cliproxyapi-usage-keeper stop || true
        ${preUpgradeBackup} || exit $?
        /sbin/rc-service lumo-cliproxyapi-usage-keeper start
        printf '%s\n' '${image}' > ${imageMarker}
      '';
}
