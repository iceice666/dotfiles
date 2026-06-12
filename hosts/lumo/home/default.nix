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

    current_services='
    lumo-postgresql
    lumo-valkey
    lumo-podman
    lumo-node-exporter
    lumo-blackbox-exporter
    lumo-prometheus
    lumo-grafana
    lumo-dynacat
    lumo-dev-port-proxy
    '

    if [ -f "$manifest" ]; then
      while IFS= read -r service; do
        [ -n "$service" ] || continue
        if ! printf '%s\n' "$current_services" | grep -qx "[[:space:]]*$service"; then
          /sbin/rc-service "$service" stop 2>/dev/null || true
          /sbin/rc-update del "$service" default 2>/dev/null || true
          rm -f "/etc/init.d/$service"
        fi
      done < "$manifest"
    fi

    printf '%s\n' "$current_services" |
      sed -e 's/^[[:space:]]*//' -e '/^$/d' > "$manifest"
    chmod 0600 "$manifest"
  '';
}
