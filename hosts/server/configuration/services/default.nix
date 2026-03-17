{ ... }:

{
  imports = [
    ./cloudflare-ips.nix
    ./cloudflared-tunnel.nix
    ./docker.nix
    ./ollama.nix
    ./openssh.nix
  ];
}
