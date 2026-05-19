{ pkgs, ... }:

{
  programs.fish.interactiveShellInit = ''
    # Shared developer environment
    set -gx PNPM_HOME $HOME/.local/share/pnpm

    if not set -q JAVA_HOME
        switch (uname)
            case Darwin
                set -l _java_home (find /Library/Java/JavaVirtualMachines -maxdepth 3 -name Home -type d 2>/dev/null | sort -V | tail -n 1)
                if test -n "$_java_home"
                    set -gx JAVA_HOME $_java_home
                end
        end
    end

    if not set -q JAVA_HOME
        set -gx JAVA_HOME ${pkgs.zulu21}
    end

    set -l _android_home_candidates
    switch (uname)
        case Darwin
            set _android_home_candidates $HOME/Library/Android/sdk
        case Linux
            set _android_home_candidates $ANDROID_HOME $HOME/Android/Sdk $HOME/.local/share/android-sdk /opt/android-sdk
    end

    if not set -q ANDROID_HOME
        for _android_home_candidate in $_android_home_candidates
            if test -d "$_android_home_candidate"
                set -gx ANDROID_HOME $_android_home_candidate
                break
            end
        end
    end

    if set -q ANDROID_HOME
        set -gx ANDROID_SDK_ROOT $ANDROID_HOME
        fish_add_path -p $ANDROID_HOME/cmdline-tools/latest/bin
        fish_add_path -p $ANDROID_HOME/emulator
        fish_add_path -p $ANDROID_HOME/platform-tools

        set -l _ndk_home (find $ANDROID_SDK_ROOT/ndk -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort -V | tail -n 1)
        if test -z "$_ndk_home"; and test (uname) = Darwin
            set _ndk_home /opt/homebrew/share/android-ndk
        end

        if test -d "$_ndk_home"
            set -gx ANDROID_NDK_HOME $_ndk_home
            fish_add_path -p $ANDROID_NDK_HOME
        end
    end

    fish_add_path -p $JAVA_HOME/bin
    fish_add_path -p $PNPM_HOME
    fish_add_path -p ~/.bun/bin
    fish_add_path -p ~/.npm-global/bin
    fish_add_path -p $HOME/.dotnet/tools
  '';
}
