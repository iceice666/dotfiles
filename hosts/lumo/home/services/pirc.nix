{ lib, pkgs, ... }:

let
  daemon = pkgs.writeText "lumo-pirc-daemon" ''
    #!/sbin/openrc-run
    name="lumo-pirc-daemon"
    description="pirc central daemon"
    supervisor=supervise-daemon
    command="${pkgs.pirc}/bin/pirc"
    command_args="gateway"
    command_user="pirc:pirc"
    directory="/var/lib/pirc"
    output_log="/var/log/lumo/pirc-daemon.log"
    error_log="/var/log/lumo/pirc-daemon.log"
    respawn_delay=5
    respawn_max=0

    depend() { need net; }
    start_pre() {
      checkpath -d -m 0700 -o pirc:pirc /var/lib/pirc
      checkpath -f -m 0640 -o pirc:root /var/log/lumo/pirc-daemon.log
      test -r /etc/pirc/daemon.env || return 1
    }
    start() {
      . /etc/pirc/daemon.env
      export PIRC_HOST PIRC_PORT PIRC_STATE_DIR PIRC_HOST_ID PIRC_WORKSPACES PIRC_TRUSTED_PROXIES
      export PIRC_ALLOWED_USERS PIRC_ALLOWED_ORIGINS PIRC_ALLOWED_HOSTS PIRC_IDENTITY_HEADER PIRC_NODE_TOKENS PIRC_DAEMON_ONLY
      supervise-daemon lumo-pirc-daemon --start --respawn-delay 5 \
        --user pirc:pirc --chdir /var/lib/pirc --stdout /var/log/lumo/pirc-daemon.log \
        --stderr /var/log/lumo/pirc-daemon.log -- ${pkgs.pirc}/bin/pirc gateway
    }
  '';
  web = pkgs.writeText "lumo-pirc-web" ''
    #!/sbin/openrc-run
    name="lumo-pirc-web"
    description="pirc static web assets"
    supervisor=supervise-daemon
    command="${pkgs.python3}/bin/python3"
    command_args="-m http.server 18788 --bind 127.0.0.1 --directory ${pkgs.pirc}/share/pirc/web"
    command_user="pirc:pirc"
    output_log="/var/log/lumo/pirc-web.log"
    error_log="/var/log/lumo/pirc-web.log"
    respawn_delay=5
    respawn_max=0
    start_pre() {
      checkpath -f -m 0640 -o pirc:root /var/log/lumo/pirc-web.log
    }
  '';
in
{
  home.activation.lumoPirc = lib.hm.dag.entryAfter [ "lumoDirectories" ] ''
    if ! /usr/bin/getent group pirc >/dev/null; then
      /usr/sbin/addgroup -S pirc
    fi
    if ! /usr/bin/id pirc >/dev/null 2>&1; then
      /usr/sbin/adduser -S -D -H -h /var/lib/pirc -s /sbin/nologin -G pirc pirc
    fi
    install -d -m 0700 -o pirc -g pirc /var/lib/pirc
    install -Dm755 ${daemon} /etc/init.d/lumo-pirc-daemon
    install -Dm755 ${web} /etc/init.d/lumo-pirc-web
    /sbin/rc-update add lumo-pirc-daemon default
    /sbin/rc-update add lumo-pirc-web default
    if test -f /etc/pirc/daemon.env; then
      /sbin/rc-service lumo-pirc-daemon restart
    fi
    /sbin/rc-service lumo-pirc-web restart
  '';
}
