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

  modules = [
    inputs.xlibre-overlay.nixosModules.overlay-xlibre-xserver
    inputs.xlibre-overlay.nixosModules.overlay-xlibre-xf86-input-libinput
    ./configuration
  ];
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
    sopsNix = inputs.sops-nix;
  };

}
