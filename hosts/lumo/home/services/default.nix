{ ... }:

{
  imports = [
    ./audit.nix
    ./cliproxyapi.nix
    ./database.nix
    ./dev-port-proxy.nix
    ./dynacat.nix
    ./edge
    ./git-server.nix
    ./monitoring.nix
    ./podman.nix
    ./umami.nix
    ./wifi.nix
  ];
}
