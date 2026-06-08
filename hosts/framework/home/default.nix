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
    ./gui.nix
  ];

  _module.args = {
    inherit desktopWallpaper;
    avatarImage = frameworkAvatar;
    ghosttyFontSize = 14;
    themegenHost = "framework";
  };

  home.packages = with pkgs; [
    obs-studio
  ];
}
