{ ... }:

{
  imports = [
    ./audit.nix
    ./database.nix
    ./dev-port-proxy.nix
    ./dynacat.nix
    ./git-server.nix
    ./monitoring.nix
    ./podman.nix
  ];
}
