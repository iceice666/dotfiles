{ ... }:

{
  imports = [
    ./cloudflared-tunnel.nix
    ./docker.nix
    ./ollama.nix
    ./openssh.nix
  ];
}
