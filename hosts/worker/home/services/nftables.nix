# Minimal worker firewall: SSH from the LAN, Tailscale, podman, and nothing
# inbound from the internet. No edge ports — that role lives on lumo.
# Keep in sync with scripts/alpine-bootstrap's worker branch.
{ lib, pkgs, ... }:

let
  nftablesFile = pkgs.writeText "dotfiles.nft" ''
    table inet dotfiles {
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
  home.activation.workerNftables = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    install -Dm644 ${nftablesFile} /etc/nftables.d/dotfiles.nft
    /sbin/rc-service dotfiles-firewall restart || true
  '';
}
