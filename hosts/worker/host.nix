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
    omp = false;
  };

  extraSpecialArgs = {
    homolab = import (dotfiles + /lib/homolab.nix);
  };

  deploy = {
    enable = true;
    # Reached over the tailnet (LAN sshd is publickey-only; tailscale SSH
    # authenticates tailnet peers).
    hostname = "worker";
    sshUser = "root";
    sshOpts = [
      "-o"
      "StrictHostKeyChecking=accept-new"
    ];
    remoteBuild = true;
    profileUser = "root";
  };
}
