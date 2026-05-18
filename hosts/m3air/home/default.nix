{
  inputs,
  pkgs,
  dotfiles,
  ...
}:

let
  desktopWallpaper = dotfiles + /assets/win_chan.jpg;
in
{
  imports = [
    inputs.sops-nix.homeManagerModules.sops
    (dotfiles + /common/home)
    ./appearance.nix
    ./default-apps.nix
    ./karabiner.nix
    ./wallpaper.nix
  ];

  _module.args = {
    inherit desktopWallpaper;
  };

  home.packages = with pkgs; [
    obsidian
    ssh-to-age
  ];

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
