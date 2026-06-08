{ ... }:

{
  name = "framework";
  kind = "nixos";
  system = "x86_64-linux";
  username = "iceice666";
  homeDirectory = "/home/iceice666";

  modules = [ ./configuration ];

  features = {
    homeManager = true;
    sops = true;
  };

  deploy = {
    enable = true;
    hostname = "framework";
    fastConnection = true;
    sshUser = "iceice666";
  };
}
