# Edge services that moved onto lumo when the gateway Pi was retired:
# Authelia SSO, Traefik reverse proxy, Cloudflare DDNS + IP-set refresh, and
# the merged firewall.
{ ... }:

{
  imports = [
    ./authelia.nix
    ./cloudflare-ddns.nix
    ./cloudflare-ips.nix
    ./nftables.nix
    ./traefik.nix
  ];
}
