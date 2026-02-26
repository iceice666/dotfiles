{ username, homeDirectory, ... }:

{
  imports = [
    ../../../common/home
    ../../../shared/home/zed.nix
  ];

  home.stateVersion = "25.11";

  programs.fish.interactiveShellInit = ''
    # Linux-specific environment variables
    set -gx HOSTNAME (hostname)
    set -gx PNPM_HOME $HOME/.local/share/pnpm

    # Linux-specific PATH
    fish_add_path -p $PNPM_HOME
  '';
}
