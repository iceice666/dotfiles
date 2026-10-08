{
  pkgs,
  dotfiles,
  ...
}:

let
  frameworkAvatar = dotfiles + /assets/framework-avatar.png;
in
{
  imports = [
    (dotfiles + /common/home-base/browser.nix)
    ./gui.nix
  ];

  _module.args = {
    avatarImage = frameworkAvatar;
    kittyFontSize = 14;
    themegenHost = "framework";
  };

  home.packages = with pkgs; [
    obs-studio
  ];
}
