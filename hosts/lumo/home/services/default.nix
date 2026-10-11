{ ... }:

{
  imports = [
    ./audit.nix
    ./blocky.nix
    ./cliproxyapi.nix
    ./cliproxyapi-usage-keeper.nix
    ./database.nix
    ./dev-port-proxy.nix
    ./dynacat.nix
    ./edge
    ./forgejo-woodpecker.nix
    ./git-server.nix
    ./monitoring.nix
    ./podman.nix
    ./umami.nix
    ./wifi.nix
  ];
}
