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
  ];

  sops.age.keyFile = "${homeDirectory}/.config/sops/age/keys.txt";

  home.stateVersion = "25.11";

  home.packages = [
    unstablePkgs.woodpecker-cli
  ];

  programs.fish.interactiveShellInit = ''
    set -gx HOSTNAME (hostname)
  '';
}
