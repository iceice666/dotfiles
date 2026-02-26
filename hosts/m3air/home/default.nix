{ pkgs, username, homeDirectory, ... }:

{
  imports = [
    ../../../common/home
    ../../../shared/home/zed.nix
  ];

  home.packages = with pkgs; [
    obsidian
    pear-desktop
    equibop-bin
  ];

  home.stateVersion = "25.11";

  programs.fish.interactiveShellInit = ''
    # macOS-specific environment variables
    set -gx HOSTNAME (hostname)
    set -gx DOTNET_ROOT /usr/local/share/dotnet/
    set -gx JAVA_HOME (ls -d /Library/Java/JavaVirtualMachines/*/Contents/Home/ 2>/dev/null | sort -V | tail -n 1)
    set -gx ANDROID_HOME $HOME/Library/Android/sdk
    set -gx ANDROID_SDK_ROOT $ANDROID_HOME
    set -gx ANDROID_NDK_HOME (ls -d $ANDROID_SDK_ROOT/ndk/*/ 2>/dev/null | sort -V | tail -n 1)
    set -gx HOMEBREW_NO_ENV_HINTS 1
    set -gx CHROME_EXECUTABLE /Applications/Helium.app/Contents/MacOS/Helium

    # macOS-specific PATH
    fish_add_path -p $ANDROID_HOME/cmdline-tools/latest/bin
    fish_add_path -p $ANDROID_HOME/platform-tools
    fish_add_path -p /opt/X11/bin
    fish_add_path -p ~/.orbstack/bin
    fish_add_path -p /opt/homebrew/sbin
    fish_add_path -p /opt/homebrew/bin
  '';
}
