{
  inputs,
  dotfiles,
  name,
}:

{
  inherit name;
  kind = "nixos";
  system = "x86_64-linux";
  username = "iceice666";
  homeDirectory = "/home/iceice666";

  modules = [ ./configuration ];
  homeModules = [ ./home ];

  features = {
    homeManager = true;
    sops = true;
    gui = true;
    themegen = true;
    rime = true;
    devEnv = true;
    pi = true;
    kaguya = true;
    nirinit = true;
  };

  deploy = {
    enable = true;
    hostname = name;
    fastConnection = true;
    sshUser = "iceice666";
  };
}
