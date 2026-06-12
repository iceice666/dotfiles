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
        ip protocol icmp accept
        ip6 nexthdr ipv6-icmp accept
        udp dport 41641 accept
        ip saddr 192.168.1.0/24 tcp dport 22 accept
        ip saddr @cloudflare_v4 tcp dport { 80, 443 } accept
        ip6 saddr @cloudflare_v6 tcp dport { 80, 443 } accept
        ip saddr 192.168.1.0/24 tcp dport { 80, 443 } accept
        ip saddr 192.168.1.0/24 tcp dport { 18081, 18082 } accept
      }

      chain forward {
        type filter hook forward priority filter; policy drop;
      }

      chain output {
        type filter hook output priority filter; policy accept;
      }
    }
  '';
in
{
  # Keep the gateway nftables file in sync with scripts/alpine-bootstrap.
  # This activation updates the file so that the cloudflare named sets exist
  # before gateway-cloudflare-ips attempts to populate them.
  home.activation.gatewayNftables = lib.hm.dag.entryBefore [ "gatewayCloudflareIps" ] ''
    install -Dm644 ${nftablesFile} /etc/nftables.d/dotfiles.nft
  '';
}
