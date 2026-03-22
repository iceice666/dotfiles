{ ... }:

{
  imports = [
    ./authelia.nix
    ./cloudflare-ddns.nix
    ./cloudflare-ips.nix
    ./cloudflared-tunnel.nix
    ./docker.nix
    ./forgejo.nix
    ./ollama.nix
    ./openssh.nix
    ./database.nix
    ./traefik.nix
    ./woodpecker.nix
  ];
}
