{
  config,
  dotfiles,
  homolab,
  lib,
  pkgs,
  ...
}:

let
  postgresPackage = pkgs.postgresql_17.withPackages (ps: [ ps.pgvector ]);
  postgresData = "/var/lib/postgresql/17/data";
  postgresConfig = pkgs.writeText "postgresql.conf" ''
    listen_addresses = '''
    port = ${toString homolab.ports.postgresql}
    unix_socket_directories = '/run/postgresql'
  '';

  postgresService = pkgs.writeText "lumo-postgresql" ''
    #!/sbin/openrc-run
    name="lumo-postgresql"
    description="Lumo PostgreSQL 17"
    supervisor=supervise-daemon
    command="${postgresPackage}/bin/postgres"
    command_args="-D ${postgresData} -c config_file=${postgresConfig}"
    command_user="postgres:postgres"
    directory="${postgresData}"
    export LANG=C
    export LC_ALL=C
    output_log="/var/log/lumo/postgresql.log"
    error_log="/var/log/lumo/postgresql.log"
    respawn_delay=5
    respawn_max=0

    depend() {
      need localmount
      after networking
    }

    start_pre() {
      checkpath -f -m 0640 -o postgres:postgres /var/log/lumo/postgresql.log
      checkpath -d -m 0750 -o postgres:postgres /run/postgresql
      checkpath -d -m 0750 -o postgres:postgres /var/lib/postgresql /var/lib/postgresql/17
      checkpath -d -m 0700 -o postgres:postgres ${postgresData}
      if [ ! -s ${postgresData}/PG_VERSION ]; then
        ${pkgs.util-linux}/bin/runuser -u postgres -- \
          ${postgresPackage}/bin/initdb -D ${postgresData} \
          --locale=C --encoding=UTF8 \
          --auth-local=peer --auth-host=scram-sha-256
      fi
    }
  '';

  valkeyBaseConfig = pkgs.writeText "valkey.conf" ''
    bind 127.0.0.1
    port 6379
    protected-mode yes
    appendonly yes
    dir /var/lib/valkey
    dbfilename dump.rdb
    appendfilename appendonly.aof
    rename-command FLUSHALL lumo_FLUSHALL
    rename-command FLUSHDB lumo_FLUSHDB
    rename-command DEBUG ""
    rename-command CONFIG lumo_CONFIG
  '';

  valkeySecret = config.sops.secrets.valkey-requirepass.path;
  valkeyService = pkgs.writeText "lumo-valkey" ''
    #!/sbin/openrc-run
    name="lumo-valkey"
    description="Lumo Valkey"
    supervisor=supervise-daemon
    command="${pkgs.valkey}/bin/valkey-server"
    command_args="/run/lumo-valkey/valkey.conf"
    command_user="valkey:valkey"
    output_log="/var/log/lumo/valkey.log"
    error_log="/var/log/lumo/valkey.log"
    respawn_delay=5
    respawn_max=0

    depend() {
      need localmount
      after networking
    }

    start_pre() {
      checkpath -f -m 0640 -o valkey:valkey /var/log/lumo/valkey.log
      checkpath -d -m 0750 -o valkey:valkey /var/lib/valkey
      checkpath -d -m 0750 -o valkey:valkey /run/lumo-valkey
      cp ${valkeyBaseConfig} /run/lumo-valkey/valkey.conf
      password="$(cat ${valkeySecret})"
      printf 'requirepass "%s"\n' "$password" >> /run/lumo-valkey/valkey.conf
      chown valkey:valkey /run/lumo-valkey/valkey.conf
      chmod 0400 /run/lumo-valkey/valkey.conf
    }
  '';
in
{
  home.packages = [
    postgresPackage
    pkgs.valkey
  ];

  sops.secrets.valkey-requirepass = {
    sopsFile = dotfiles + /sensitive/hosts/lumo/valkey.yaml;
    key = "requirepass";
    mode = "0400";
  };

  home.activation.lumoDatabase = lib.hm.dag.entryAfter [ "lumoDirectories" ] ''
    install -d -m 0755 /var/log/lumo

    if ! /usr/bin/getent group postgres >/dev/null; then
      /usr/sbin/addgroup -S postgres
    fi
    if ! /usr/bin/id postgres >/dev/null 2>&1; then
      /usr/sbin/adduser -S -D -H -h /var/lib/postgresql -s /sbin/nologin -G postgres postgres
    fi

    if ! /usr/bin/getent group valkey >/dev/null; then
      /usr/sbin/addgroup -S valkey
    fi
    if ! /usr/bin/id valkey >/dev/null 2>&1; then
      /usr/sbin/adduser -S -D -H -h /var/lib/valkey -s /sbin/nologin -G valkey valkey
    fi

    install -Dm755 ${postgresService} /etc/init.d/lumo-postgresql
    install -Dm755 ${valkeyService} /etc/init.d/lumo-valkey
    /sbin/rc-update add lumo-postgresql default
    /sbin/rc-update add lumo-valkey default
    /sbin/rc-service lumo-postgresql restart
    /sbin/rc-service lumo-valkey restart
  '';
}
