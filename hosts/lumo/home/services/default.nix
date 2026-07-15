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
    ./honcho.nix
    ./hermes-agent
    ./monitoring.nix
    ./ntfy.nix
    ./podman.nix
    ./tempestmiku-embeddings.nix
    ./tempestmiku
    ./umami.nix
  ];
}
