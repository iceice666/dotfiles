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
    pi = true;
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
    # deploy-rs's magic-rollback confirmation defaults to 30s. lumo's
    # activation chain (20+ home.activation.* hooks: package installs,
    # service group setup, several `rc-service restart`s) routinely runs
    # past that window even when activation succeeds, so deploy-rs
    # auto-rolls-back a healthy generation. Give it real headroom.
    confirmTimeout = 180;
  };
}
