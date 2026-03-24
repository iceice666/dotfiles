{
  pkgs,
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
    pkgs.woodpecker-cli-unstable
  ];

  programs.fish.interactiveShellInit = ''
    set -gx HOSTNAME (hostname)
  '';
}
