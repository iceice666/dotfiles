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
    ./git-server.nix
    ./monitoring.nix
    ./podman.nix
    ./umami.nix
    ./wifi.nix
  ];
}
