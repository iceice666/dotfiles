# Edge firewall ruleset for lumo.
#
# Merges lumo's host rules (podman + app ports proxied from homolab/self) with
# the edge rules (Cloudflare IP sets + 80/443 + traefik ping/metrics) that
# moved here from the retired gateway Pi. Mirror any change in
# scripts/alpine-bootstrap's lumo branch so a fresh bootstrap matches.
{ lib, pkgs, ... }:

let
  nftablesFile = pkgs.writeText "dotfiles.nft" ''
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
        # app ports proxied from homolab and lumo itself (Traefik backends)
        ip saddr { 192.168.1.127, 192.168.1.128 } tcp dport { 18075, 18076, 18084, 20129 } accept
        # edge: HTTP/HTTPS from Cloudflare IP sets and the LAN
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
  # The Cloudflare named sets must exist before lumo-cloudflare-ips populates them.
  home.activation.lumoEdgeNftables = lib.hm.dag.entryBefore [ "lumoCloudflareIps" ] ''
    install -Dm644 ${nftablesFile} /etc/nftables.d/dotfiles.nft
  '';
}
