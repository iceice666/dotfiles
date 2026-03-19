{ ... }:

{
  imports = [
    ./caddy.nix
    ./cloudflare-ips.nix
    ./cloudflared-tunnel.nix
    ./docker.nix
    ./forgejo.nix
    ./ollama.nix
    ./openssh.nix
    ./database.nix
  ];
}
