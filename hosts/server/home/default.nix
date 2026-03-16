{
  username,
  homeDirectory,
  dotfiles,
  ...
}:

{
  imports = [
    (dotfiles + /common/home)
  ];

  home.stateVersion = "25.05";

  programs.fish.interactiveShellInit = ''
    set -gx HOSTNAME (hostname)
  '';
}
