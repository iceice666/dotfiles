{ lib, pkgs, ... }:

let
  refreshScript = pkgs.writeShellApplication {
    name = "lumo-cloudflare-ips-refresh";
    runtimeInputs = [
      pkgs.curl
      pkgs.nftables
    ];
    text = ''
      set -euo pipefail

      state_dir=/var/lib/cloudflare-ips
      ipv4_file="$state_dir/ips-v4"
      ipv6_file="$state_dir/ips-v6"

      fetch_with_retry() {
        local url="$1" output="$2"
        for _ in $(seq 1 20); do
          if curl --fail --silent --show-error "$url" -o "$output"; then
            return 0
          fi
          sleep 3
        done
        printf 'Failed to fetch %s after retries.\n' "$url" >&2
        return 1
      }

      mkdir -p "$state_dir"
      fetch_with_retry https://www.cloudflare.com/ips-v4 "$ipv4_file"
      fetch_with_retry https://www.cloudflare.com/ips-v6 "$ipv6_file"

      test -s "$ipv4_file"
      test -s "$ipv6_file"

      # Build nft batch to atomically flush and repopulate Cloudflare sets.
      {
        printf 'flush set inet dotfiles cloudflare_v4\n'
        printf 'flush set inet dotfiles cloudflare_v6\n'
        printf 'table inet dotfiles {\n'
        printf '  set cloudflare_v4 {\n    type ipv4_addr\n    flags interval\n    auto-merge\n'
        printf '    elements = { '
        tr '\n' ',' < "$ipv4_file" | sed 's/,$//'
        printf ' }\n  }\n'
        printf '  set cloudflare_v6 {\n    type ipv6_addr\n    flags interval\n    auto-merge\n'
        printf '    elements = { '
        tr '\n' ',' < "$ipv6_file" | sed 's/,$//'
        printf ' }\n  }\n'
        printf '}\n'
      } | nft -f -
    '';
  };

  ipsService = pkgs.writeText "lumo-cloudflare-ips" ''
    #!/sbin/openrc-run
    name="lumo-cloudflare-ips"
    description="Refresh Cloudflare IP sets in nftables"

    depend() {
      need net dotfiles-firewall
    }

    start() {
      ebegin "Refreshing Cloudflare IP sets"
      ${refreshScript}/bin/lumo-cloudflare-ips-refresh
      eend $?
    }
  '';
in
{
  home.packages = [ refreshScript ];

  home.activation.lumoCloudflareIps = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    install -Dm755 ${ipsService} /etc/init.d/lumo-cloudflare-ips
    /sbin/rc-update add lumo-cloudflare-ips default
    # --nodeps: lumo-cloudflare-ips `need`s dotfiles-firewall, so a plain
    # restart here would have OpenRC cascade-restart the already-running
    # lumo-cloudflare-ips itself, racing with the explicit restart below
    # (flock contention, duplicate concurrent curl fetches against
    # www.cloudflare.com).
    /sbin/rc-service --nodeps dotfiles-firewall restart
    # restart, not start: this is a oneshot service, so once it is
    # marked started a plain `start` is a no-op and the IP-set refresh would
    # never run again on later deploys.
    /sbin/rc-service lumo-cloudflare-ips restart || true
  '';
}
