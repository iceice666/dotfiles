{ ... }:

{
  imports = [
    ./audit.nix
    ./cliproxyapi.nix
    ./database.nix
    ./dev-port-proxy.nix
    ./dynacat.nix
    ./git-server.nix
    ./honcho.nix
    ./hermes-agent.nix
    ./monitoring.nix
    ./podman.nix
  ];
}
