# TEMPORARY gateway failover.
#
# The gateway host device (192.168.1.129, edge) is unavailable, so lumo
# (192.168.1.128, apps) temporarily takes over gateway's edge services:
# Authelia SSO, Traefik reverse proxy, Cloudflare DDNS + IP-set refresh, and
# the wake-on-LAN helper.
#
# Two of gateway's modules are intentionally NOT imported:
#   * node-exporter.nix — would bind 0.0.0.0:19100, colliding with
#     lumo-node-exporter which already listens on 127.0.0.1:19100.
#   * nftables.nix — its ruleset drops lumo's podman/app rules. The merged
#     ruleset below keeps both lumo's and gateway's input/forward rules.
#
# To revert when the gateway host is back:
#   1. Remove ./gateway-failover.nix from ./default.nix imports.
#   2. Remove the gateway-* entries from current_services in ../default.nix
#      (so the openrc services get torn down on the next deploy).
#   3. Drop *lumo from the gateway rule in .sops.yaml and re-run
#      `sops updatekeys` on the gateway secrets.
#   4. Deploy lumo, then restore the bootstrap firewall (lumo-switch rewrites
#      it) — re-run alpine-bootstrap's firewall step or `just lumo-switch`.
{
  dotfiles,
  lib,
  pkgs,
  ...
}:

let
  # Merge of lumo's bootstrap ruleset (podman + app ports) with gateway's edge
  # ruleset (Cloudflare sets + 80/443 + traefik ping/metrics). 192.168.1.128
  # (lumo itself) is added to the app-port source set because Traefik now
  # proxies to lumo's own LAN address.
  mergedNftables = pkgs.writeText "dotfiles.nft" ''
    table inet dotfiles {
      set cloudflare_v4 {
        type ipv4_addr
        flags interval
        auto-merge
      }
      set cloudflare_v6 {
        type ipv6_addr
        flags interval
        auto-merge
      }

      chain input {
        type filter hook input priority filter; policy drop;
        ct state established,related accept
        iifname "lo" accept
        iifname "tailscale0" accept
        iifname "podman*" accept
        ip protocol icmp accept
        ip6 nexthdr ipv6-icmp accept
        udp dport 41641 accept
        ip saddr 192.168.1.0/24 tcp dport 22 accept
        # lumo app ports proxied from gateway/homolab and now self
        ip saddr { 192.168.1.127, 192.168.1.128, 192.168.1.129 } tcp dport { 18075, 18076, 18084, 20129 } accept
        # gateway edge: HTTP/HTTPS from Cloudflare IP sets and the LAN
        ip saddr @cloudflare_v4 tcp dport { 80, 443 } accept
        ip6 saddr @cloudflare_v6 tcp dport { 80, 443 } accept
        ip saddr 192.168.1.0/24 tcp dport { 80, 443 } accept
        # traefikPing (18081) and traefikMetrics (18082): LAN only
        ip saddr 192.168.1.0/24 tcp dport { 18081, 18082 } accept
      }

      chain forward {
        type filter hook forward priority filter; policy drop;
        iifname "podman*" accept
        oifname "podman*" accept
      }

      chain output {
        type filter hook output priority filter; policy accept;
      }
    }
  '';
in
{
  imports = [
    (dotfiles + /hosts/gateway/home/services/authelia.nix)
    (dotfiles + /hosts/gateway/home/services/cloudflare-ddns.nix)
    (dotfiles + /hosts/gateway/home/services/cloudflare-ips.nix)
    (dotfiles + /hosts/gateway/home/services/traefik.nix)
    (dotfiles + /hosts/gateway/home/services/wol.nix)
  ];

  # Replaces gateway's nftables.nix. Must land before gateway-cloudflare-ips
  # refreshes the Cloudflare sets it declares.
  home.activation.gatewayFailoverNftables = lib.hm.dag.entryBefore [ "gatewayCloudflareIps" ] ''
    install -Dm644 ${mergedNftables} /etc/nftables.d/dotfiles.nft
  '';
}
