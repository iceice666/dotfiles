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

  home.stateVersion = "25.11";

  programs.fish.interactiveShellInit = ''
    set -gx HOSTNAME (hostname)
  '';
}
