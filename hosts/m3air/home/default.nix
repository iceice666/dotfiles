{ pkgs, username, homeDirectory, ... }:

{
  imports = [
    ../../../common/home
    ../../../shared/home/zed.nix
    ../../../shared/home/opencode.nix
    ./aerospace.nix
  ];

  home.packages = with pkgs; [
    obsidian
    pear-desktop
    equibop-bin
    aerospace-swipe
  ];

  home.stateVersion = "25.11";

  programs.fish.interactiveShellInit = ''
    # macOS-specific environment variables
    set -gx HOSTNAME (hostname)
    set -gx DOTNET_ROOT /usr/local/share/dotnet/

    # JAVA_HOME: pick latest JVM if any are installed
    set -l _java_home (find /Library/Java/JavaVirtualMachines -maxdepth 3 -name Home -type d 2>/dev/null | sort -V | tail -n 1)
    if test -n "$_java_home"
        set -gx JAVA_HOME $_java_home
    end

    # Android SDK (managed by android-commandlinetools cask via sdkmanager)
    set -gx ANDROID_HOME $HOME/Library/Android/sdk
    set -gx ANDROID_SDK_ROOT $ANDROID_HOME

    # Android NDK: prefer versioned NDK under SDK root, fall back to Homebrew cask path
    set -l _ndk_home (find $ANDROID_SDK_ROOT/ndk -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort -V | tail -n 1)
    if test -z "$_ndk_home"
        set _ndk_home /opt/homebrew/share/android-ndk
    end
    if test -d "$_ndk_home"
        set -gx ANDROID_NDK_HOME $_ndk_home
        fish_add_path -p $ANDROID_NDK_HOME
    end

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
