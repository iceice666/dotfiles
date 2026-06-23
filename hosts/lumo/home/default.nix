{
  pkgs,
  dotfiles,
  lib,
  ...
}:

{
  imports = [
    (dotfiles + /common/home-alpine)
    ./services
  ];

  home.packages = with pkgs; [
    claude-code-bin
    oh-my-pi-bin
  ];

  home.activation.claudeLocalBin = lib.hm.dag.entryAfter [ "claude-remove-self-install-shim" ] ''
    install -dm755 "$HOME/.local/bin"
    claude_link="$HOME/.local/bin/claude"
    claude_versions="$HOME/.local/share/claude/versions"

    rm -f "$claude_link"
    ln -s "${pkgs.claude-code-bin}/bin/claude" "$claude_link"

    chmod u+w "$claude_versions" 2>/dev/null || true
    find "$claude_versions" -maxdepth 1 -mindepth 1 -delete 2>/dev/null || true
    mkdir -p "$claude_versions"
    chmod 555 "$claude_versions"
  '';

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
    lumo-cliproxyapi
    lumo-honcho-postgres
    lumo-honcho-redis
    lumo-honcho-api
    lumo-honcho-deriver
    lumo-hermes-agent
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
