{
  config,
  dotfiles,
  homolab,
  lib,
  pkgs,
  ...
}:

let
  ddnsTokenPath = config.sops.secrets.cloudflare-ddns-key.path;

  ddnsLoop = pkgs.writeShellScript "lumo-cloudflare-ddns-loop" ''
    set -eu
    while true; do
      ${pkgs.cloudflare-dyndns}/bin/cloudflare-dyndns \
        --api-token-file '${ddnsTokenPath}' \
        --proxied \
        -4 -no-6 \
        --cache-file /var/lib/cloudflare-ddns/ip.cache \
        ${homolab.domains.root} || true
      sleep 3600
    done
  '';

  ddnsService = pkgs.writeText "lumo-cloudflare-ddns" ''
    #!/sbin/openrc-run
    name="lumo-cloudflare-ddns"
    description="Lumo Cloudflare DDNS updater"
    supervisor=supervise-daemon
    command="${ddnsLoop}"
    output_log="/var/log/lumo/cloudflare-ddns.log"
    error_log="/var/log/lumo/cloudflare-ddns.log"
    respawn_delay=5
    respawn_max=0

    depend() {
      need net
    }

    start_pre() {
      checkpath -d -m 0755 -o root:root /var/log/lumo
      checkpath -d -m 0700 -o root:root /var/lib/cloudflare-ddns
      checkpath -f -m 0640 -o root:root /var/log/lumo/cloudflare-ddns.log
    }
  '';
in
{
  sops.secrets.cloudflare-ddns-key = {
    sopsFile = dotfiles + /sensitive/hosts/lumo/cloudflare-ddns.key;
    format = "binary";
    mode = "0400";
  };

  home.activation.lumoCloudflareGns = lib.hm.dag.entryAfter [ "sopsAlpine" ] ''
    install -Dm755 ${ddnsService} /etc/init.d/lumo-cloudflare-ddns
    /sbin/rc-update add lumo-cloudflare-ddns default
    /sbin/rc-service lumo-cloudflare-ddns restart
  '';
}
