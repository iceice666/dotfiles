{ username, homeDirectory, ... }:

{
  imports = [ ../../user/home-base.nix ];

  home.stateVersion = "25.05";

  programs.fish.interactiveShellInit = ''
    set -gx HOSTNAME (hostname)
  '';
}
