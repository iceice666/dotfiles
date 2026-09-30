{ dotfiles, ... }:

let
  desktopWallpaper = dotfiles + /assets/win_chan.jpg;
in
{
  imports = [
    (dotfiles + /common/home-base/browser.nix)
    # pirc node itself is managed manually (binary + launchd plist in
    # ~/.local/pirc-node), like m3air; only its agent config stays here.
    (dotfiles + /common/home-base/pirc-agent.nix)
    ./appearance.nix
    ./default-apps.nix
    ./dsh-desktop.nix
    ./karabiner.nix
    ./sleepguard.nix
    ./wallpaper.nix
  ];

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
