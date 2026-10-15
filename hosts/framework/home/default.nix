{
  lib,
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
    ghosttyFontSize = 14;
    themegenHost = "framework";
  };

  # Framework uses Niri for window management; no Ghostty tab bar.
  programs.ghostty.settings.window-show-tab-bar = lib.mkForce "never";

  home.packages = with pkgs; [
    obs-studio
  ];
}
