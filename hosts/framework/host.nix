{
  inputs,
  dotfiles,
  name,
  ...
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
    nirinit = true;
  };

  extraSpecialArgs = {
    # Static login-screen (regreet) wallpaper.
    desktopWallpaper = dotfiles + /assets/mzen.png;
    # Desktop rotation set: darkman picks a random one at sunrise/sunset.
    desktopWallpapers = map (name: dotfiles + "/assets/${name}") [
      "isekaijoucho/p1.jpg"
      "isekaijoucho/p2.jpg"
    ];
    homolab = import (dotfiles + /lib/homolab.nix);
  };

  deploy = {
    enable = true;
    hostname = name;
    fastConnection = true;
    sshUser = "iceice666";
  };
}
