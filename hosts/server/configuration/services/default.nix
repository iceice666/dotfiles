{ ... }:

{
  imports = [
    ./authelia.nix
    ./cloudflare-ddns.nix
    ./cloudflare-ips.nix
    ./cloudflared-tunnel.nix
    ./daily-audit.nix
    ./dynacat.nix
    ./dnsmasq.nix
    ./docker.nix
    ./forgejo.nix
    ./ollama.nix
    ./openssh.nix
    ./database.nix
    ./rustfs.nix
    ./traefik.nix
    ./woodpecker.nix
  ];
}
