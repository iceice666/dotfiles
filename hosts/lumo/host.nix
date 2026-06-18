{ dotfiles, name, ... }:

{
  inherit name;
  kind = "home-manager";
  system = "aarch64-linux";
  username = "root";
  homeDirectory = "/root";
  homeModules = [ ./home ];

  features = {
    homeManager = true;
    sops = true;
    gui = false;
    devEnv = false;
    omp = true;
  };

  extraSpecialArgs = {
    homolab = import (dotfiles + /lib/homolab.nix);
  };

  deploy = {
    enable = true;
    hostname = name;
    sshUser = "root";
    sshOpts = [
      "-p"
      "22"
    ];
    remoteBuild = true;
    profileUser = "root";
  };
}
