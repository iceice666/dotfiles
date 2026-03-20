{ ... }:

{
  imports = [
    ./cloudflare-ddns.nix
    ./cloudflare-ips.nix
    ./cloudflared-tunnel.nix
    ./docker.nix
    ./forgejo.nix
    ./nginx.nix
    ./ollama.nix
    ./openssh.nix
    ./database.nix
  ];
}
