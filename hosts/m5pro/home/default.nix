{ dotfiles, pkgs, ... }:

let
  desktopWallpaper = dotfiles + /assets/win_chan.jpg;
in
{
  imports = [
    (dotfiles + /common/home-base/browser.nix)
    ./appearance.nix
    ./default-apps.nix
    ./dsh-desktop.nix
    ./karabiner.nix
    ./omp.nix
    ./sleepguard.nix
    ./wallpaper.nix
  ];

  home.packages = [ pkgs.oh-my-pi-bin ];

  _module.args = {
    inherit desktopWallpaper;
    themegenHost = "m5pro";
    kittyFontSize = 16;
  };

  programs.fish.interactiveShellInit = ''
    # macOS-specific environment variables
    set -gx DOTNET_ROOT /usr/local/share/dotnet/

    set -gx HOMEBREW_NO_ENV_HINTS 1
    set -gx CHROME_EXECUTABLE /Applications/Helium.app/Contents/MacOS/Helium

    # macOS-specific PATH
    fish_add_path -p /opt/X11/bin
    fish_add_path -p ~/.orbstack/bin
    fish_add_path -p /opt/homebrew/sbin
    fish_add_path -p /opt/homebrew/bin
  '';
}
