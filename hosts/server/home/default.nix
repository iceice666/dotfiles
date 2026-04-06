{
  inputs,
  pkgs,
  unstablePkgs,
  username,
  homeDirectory,
  dotfiles,
  ...
}:

{
  imports = [
    inputs.sops-nix.homeManagerModules.sops
    (dotfiles + /common/home)
    (dotfiles + /shared/home/opencode.nix)
  ];

  sops.age.keyFile = "/var/lib/sops-nix/key.txt";

  home.stateVersion = "25.11";

  home.packages = [
    unstablePkgs.woodpecker-cli
  ];

  programs.fish.interactiveShellInit = ''
    set -gx HOSTNAME (hostname)
  '';
}
