{ ... }:

{
  imports = [
    ./edge.nix
    ./ai.nix
  ];

  sops = {
    defaultSopsFormat = "yaml";

    age = {
      keyFile = "/var/lib/sops-nix/key.txt";
      generateKey = false;
    };
  };

}
