{ ... }:

{
  imports = [
    ./node-exporter.nix
    ./openssh.nix
    ./tailscale.nix
  ];
}
