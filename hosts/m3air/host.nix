{
  inputs,
  dotfiles,
  name,
  ...
}:

{
  inherit name;
  kind = "darwin";
  system = "aarch64-darwin";
  username = "iceice666";
  homeDirectory = "/Users/iceice666";

  modules = [ ./configuration ];
  homeModules = [ ./home ];

  features = {
    homeManager = true;
    sops = true;
    gui = true;
    themegen = true;
    rime = true;
    devEnv = true;
    omp = true;
  };

  extraSpecialArgs = {
    homolab = import (dotfiles + /lib/homolab.nix);
  };
}
