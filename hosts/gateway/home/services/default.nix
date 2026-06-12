{ ... }:

{
  imports = [
    ./authelia.nix
    ./cloudflare-ddns.nix
    ./cloudflare-ips.nix
    ./nftables.nix
    ./node-exporter.nix
    ./traefik.nix
    ./wol.nix
  ];
}
