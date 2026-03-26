{
  unstablePkgs,
  username,
  homeDirectory,
  dotfiles,
  ...
}:

{
  imports = [
    (dotfiles + /common/home)
  ];

  home.stateVersion = "25.11";

  home.packages = [
    unstablePkgs.woodpecker-cli
  ];

  programs.fish.interactiveShellInit = ''
    set -gx HOSTNAME (hostname)
  '';
}
