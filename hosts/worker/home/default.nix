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

  home.activation.workerDirectories = lib.hm.dag.entryAfter [ "sopsAlpine" ] ''
    install -d -m 0755 /var/log/worker

    # One-time teardown of the retired gateway edge services that still linger
    # on this box from its former life as the gateway Pi.
    for stale in gateway-traefik gateway-authelia gateway-cloudflare-ddns gateway-cloudflare-ips gateway-node-exporter; do
      if [ -f "/etc/init.d/$stale" ]; then
        /sbin/rc-service "$stale" stop 2>/dev/null || true
        /sbin/rc-update del "$stale" default 2>/dev/null || true
        rm -f "/etc/init.d/$stale"
      fi
    done

    state_dir=/var/lib/dotfiles-openrc
    manifest="$state_dir/worker-services"
    install -d -m 0700 "$state_dir"

    current_services='
    worker-podman
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
