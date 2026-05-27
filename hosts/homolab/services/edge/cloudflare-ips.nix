{ pkgs, ... }:

let
  refreshCloudflareIps = pkgs.writeShellApplication {
    name = "refresh-cloudflare-ips";
    runtimeInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.curl
      pkgs.ipset
      pkgs.systemd
    ];
    text = ''
      set -euo pipefail

      state_dir=/var/lib/cloudflare-ips
      ipv4_file="$state_dir/ips-v4"
      ipv6_file="$state_dir/ips-v6"
      tmp_v4=cloudflare-v4-next
      tmp_v6=cloudflare-v6-next

      fetch_with_retry() {
        url="$1"
        output="$2"

        for _ in $(seq 1 20); do
          if curl --fail --silent --show-error "$url" -o "$output"; then
            return 0
          fi

          sleep 3
        done

        printf 'Failed to fetch %s after waiting for DNS to come online.\n' "$url" >&2
        return 1
      }

      mkdir -p "$state_dir"

      fetch_with_retry https://www.cloudflare.com/ips-v4 "$ipv4_file"
      fetch_with_retry https://www.cloudflare.com/ips-v6 "$ipv6_file"

      test -s "$ipv4_file"
      test -s "$ipv6_file"

      ipset create cloudflare-v4 hash:net family inet -exist
      ipset create cloudflare-v6 hash:net family inet6 -exist
      ipset create "$tmp_v4" hash:net family inet -exist
      ipset create "$tmp_v6" hash:net family inet6 -exist
      ipset flush "$tmp_v4"
      ipset flush "$tmp_v6"

      while IFS= read -r cidr; do
        [ -n "$cidr" ] && ipset add "$tmp_v4" "$cidr"
      done < "$ipv4_file"

      while IFS= read -r cidr; do
        [ -n "$cidr" ] && ipset add "$tmp_v6" "$cidr"
      done < "$ipv6_file"

      ipset swap cloudflare-v4 "$tmp_v4"
      ipset swap cloudflare-v6 "$tmp_v6"
      ipset destroy "$tmp_v4"
      ipset destroy "$tmp_v6"
    '';
  };
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/cloudflare-ips 0755 root root -"
  ];

  systemd.services.cloudflare-ips-refresh = {
    description = "Refresh Cloudflare IP sets";
    after = [
      "network-online.target"
      "technitium-dns-server.service"
    ];
    wants = [
      "network-online.target"
      "technitium-dns-server.service"
    ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${refreshCloudflareIps}/bin/refresh-cloudflare-ips";
    };
  };

  systemd.timers.cloudflare-ips-refresh = {
    description = "Refresh Cloudflare IP sets daily";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5m";
      OnUnitActiveSec = "1d";
      RandomizedDelaySec = "30m";
      Unit = "cloudflare-ips-refresh.service";
    };
  };
}
