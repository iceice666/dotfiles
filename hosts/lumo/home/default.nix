{
  dotfiles,
  lib,
  ...
}:

{
  imports = [
    (dotfiles + /common/home-alpine)
    ./services
  ];

  home.activation.lumoDirectories = lib.hm.dag.entryAfter [ "sopsAlpine" ] ''
    install -d -m 0755 /var/log/lumo

    state_dir=/var/lib/dotfiles-openrc
    manifest="$state_dir/lumo-services"
    install -d -m 0700 "$state_dir"

    retired_services='
    lumo-ntfy
    lumo-tempestmiku
    lumo-tempestmiku-embeddings
    lumo-tempestmiku.pre-thermal-fix
    '

    for service in $retired_services; do
      /sbin/rc-service "$service" stop 2>/dev/null || true
      /sbin/rc-update del "$service" default 2>/dev/null || true
      rm -f "/etc/init.d/$service"
    done

    current_services='
    lumo-postgresql
    lumo-blocky
    lumo-valkey
    lumo-podman
    lumo-node-exporter
    lumo-blackbox-exporter
    lumo-prometheus
    lumo-grafana
    lumo-dynacat
    lumo-dev-port-proxy
    lumo-cliproxyapi
    lumo-cliproxyapi-usage-keeper
    lumo-umami-postgres
    lumo-umami
    lumo-forgejo
    lumo-forgejo-bootstrap
    lumo-woodpecker-server
    lumo-woodpecker-agent
    lumo-authelia
    lumo-cloudflare-ddns
    lumo-cloudflare-ips
    lumo-traefik
    lumo-pirc-daemon
    lumo-pirc-web
    '

    for service_path in /etc/init.d/lumo-*; do
      [ -e "$service_path" ] || continue
      service="''${service_path##*/}"
      if ! printf '%s\n' "$current_services" | grep -qx "[[:space:]]*$service"; then
        /sbin/rc-service "$service" stop 2>/dev/null || true
        /sbin/rc-update del "$service" default 2>/dev/null || true
        rm -f "$service_path"
      fi
    done

    printf '%s\n' "$current_services" |
      sed -e 's/^[[:space:]]*//' -e '/^$/d' > "$manifest"
    chmod 0600 "$manifest"
  '';
}
