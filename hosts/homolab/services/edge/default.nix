{ ... }:

{
  imports = [
    ./authelia.nix
    ./cloudflare-ddns.nix
    ./cloudflare-ips.nix
    ./dev-port-proxy.nix
    ./dynacat.nix
    ./monitoring.nix
    ./technitium.nix
    ./openssh.nix
    ./tailscale.nix
    ./traefik.nix
  ];
}
