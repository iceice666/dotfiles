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
    ./qutebrowser
  ];

  _module.args = {
    inherit desktopWallpaper;
    avatarImage = frameworkAvatar;
    ghosttyFontSize = 14;
  };

  home.packages = with pkgs; [
    obs-studio
  ];
}
