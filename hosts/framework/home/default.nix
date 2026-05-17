{
  pkgs,
  dotfiles,
  ...
}:

let
  desktopWallpaper = dotfiles + /assets/mzen.png;
  frameworkAvatar = dotfiles + /assets/framework-avatar.png;
in
{
  imports = [
    (dotfiles + /common/home)
    ./gui.nix
  ];

  _module.args = {
    inherit desktopWallpaper;
    avatarImage = frameworkAvatar;
  };

  targets.genericLinux.enable = true;

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
