# worker is a disposable-work / agent-runtime host. It carries no persistent
# state of its own (that lives on lumo); for now it just provides a podman
# runtime for throwaway containers plus its own firewall. Add concrete
# workloads here as they come up.
{ ... }:

{
  imports = [
    ./nftables.nix
    ./podman.nix
  ];
}
