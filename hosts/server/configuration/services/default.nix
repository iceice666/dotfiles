{ ... }:

{
  imports = [
    ./authelia.nix
    ./cloudflare-ddns.nix
    ./cloudflare-ips.nix
    ./cloudflared-tunnel.nix
    ./docker.nix
    ./forgejo.nix
    ./homepage.nix
    ./ollama.nix
    ./openssh.nix
    ./database.nix
    ./rustfs.nix
    ./traefik.nix
    ./woodpecker.nix
  ];
}
