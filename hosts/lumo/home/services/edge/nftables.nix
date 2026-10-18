# Edge firewall ruleset for lumo.
#
# Application backends bind to loopback and are reached only through the
# local Traefik, so tailnet and container interfaces get explicit ports
# instead of blanket trust. Mirror any change in scripts/alpine-bootstrap's
# lumo branch so a fresh bootstrap matches.
{
  config,
  homolab,
  lib,
  pkgs,
  ...
}:

let
  forgejoSshRules = lib.optionalString config.lumo.forgejoWoodpecker.enable (
    "iifname \"tailscale0\" tcp dport 2222 accept\n"
    + "        ip saddr ${homolab.hosts.homolab.lan} tcp dport 2222 accept"
  );

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
        ip protocol icmp accept
        ip6 nexthdr ipv6-icmp accept
        udp dport 41641 accept
        ip saddr 192.168.1.0/24 tcp dport 22 accept
        # tailnet: SSH, Blocky DNS, and HTTP/HTTPS through Traefik
        iifname "tailscale0" tcp dport { 22, 53, 80, 443 } accept
        iifname "tailscale0" udp dport 53 accept
        # containers: DNS and HTTP/HTTPS through Traefik
        iifname "podman*" tcp dport { 53, 80, 443 } accept
        iifname "podman*" udp dport 53 accept
        # Forgejo SSH (only while the stack is enabled)
        ${forgejoSshRules}
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
