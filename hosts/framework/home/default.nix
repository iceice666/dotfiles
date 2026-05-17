{
  pkgs,
  dotfiles,
  ...
}:

let
  desktopWallpaper = dotfiles + /assets/mzen.png;
in
{
  imports = [
    (dotfiles + /common/home)
  ];

  _module.args = {
    inherit desktopWallpaper;
  };

  home.packages = with pkgs; [
    obs-studio
  ];

  programs.fish.interactiveShellInit = ''
    # Linux-specific environment variables
    set -gx PNPM_HOME $HOME/.local/share/pnpm

    # Linux-specific PATH
    fish_add_path -p $PNPM_HOME
  '';
}
