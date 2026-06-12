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

  ddnsLoop = pkgs.writeShellScript "gateway-cloudflare-ddns-loop" ''
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

  ddnsService = pkgs.writeText "gateway-cloudflare-ddns" ''
    #!/sbin/openrc-run
    name="gateway-cloudflare-ddns"
    description="Gateway Cloudflare DDNS updater"
    supervisor=supervise-daemon
    command="${ddnsLoop}"
    output_log="/var/log/gateway/cloudflare-ddns.log"
    error_log="/var/log/gateway/cloudflare-ddns.log"
    respawn_delay=5
    respawn_max=0

    depend() {
      need net
    }

    start_pre() {
      checkpath -d -m 0755 -o root:root /var/log/gateway
      checkpath -d -m 0700 -o root:root /var/lib/cloudflare-ddns
      checkpath -f -m 0640 -o root:root /var/log/gateway/cloudflare-ddns.log
    }
  '';
in
{
  sops.secrets.cloudflare-ddns-key = {
    sopsFile = dotfiles + /sensitive/hosts/gateway/cloudflare-ddns.key;
    format = "binary";
    mode = "0400";
  };

  home.activation.gatewayCloudflareGns = lib.hm.dag.entryAfter [ "sopsAlpine" ] ''
    install -Dm755 ${ddnsService} /etc/init.d/gateway-cloudflare-ddns
    /sbin/rc-update add gateway-cloudflare-ddns default
    /sbin/rc-service gateway-cloudflare-ddns restart
  '';
}
