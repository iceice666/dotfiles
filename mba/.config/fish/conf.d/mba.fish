# Special settings for my macbook air m3

# Environment Variables
set -gx DOTNET_ROOT /usr/local/share/dotnet/
set -gx JAVA_HOME /Library/Java/JavaVirtualMachines/zulu-21.jdk/Contents/Home/
set -gx ANDROID_NDK_HOME /opt/homebrew/share/android-ndk
set -gx ANDROID_HOME /Users/iceice666/Library/Android/sdk

# Paths
fish_add_path -p /opt/homebrew/share/android-commandlinetools/cmdline-tools/latest/bin/
fish_add_path -p /opt/X11/bin
fish_add_path -p $ANDROID_HOME/platform-tools
fish_add_path -p ~/.orbstack/bin
fish_add_path -p /opt/homebrew/sbin
fish_add_path -p /opt/homebrew/bin