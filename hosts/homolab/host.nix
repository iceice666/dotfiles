{ inputs, dotfiles }:

{
  name = "homolab";
  kind = "nixos";
  system = "x86_64-linux";
  username = "iceice666";
  homeDirectory = "/home/iceice666";

  modules = [ ./configuration ];

  features = {
    homeManager = true;
    sops = true;
  };

  extraSpecialArgs = {
    homolab = import (dotfiles + /lib/homolab.nix);
    sopsNix = inputs.sops-nix;
  };

  deploy = {
    enable = true;
    hostname = "homolab";
    sshUser = "iceice666";
    sshOpts = [
      "-p"
      "2222"
    ];
    remoteBuild = true;
  };
}
