{ username, homeDirectory, ... }:

{
  imports = [
    ../../../common/home
  ];

  home.stateVersion = "25.05";

  programs.fish.interactiveShellInit = ''
    set -gx HOSTNAME (hostname)
  '';
}
