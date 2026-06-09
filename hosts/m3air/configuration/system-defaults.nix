{ config, ... }:

let
  squirrelTraditionalInputSources = [
    {
      "Bundle ID" = "im.rime.inputmethod.Squirrel";
      "Input Mode" = "im.rime.inputmethod.Squirrel.Hant";
      InputSourceKind = "Input Mode";
    }
  ];
in
{
  # Spaces
  system.defaults.spaces.spans-displays = false;

  # Dock
  system.defaults.dock = {
    autohide = true;
    autohide-delay = 0.0;
    autohide-time-modifier = 0.5;
    orientation = "bottom";
    tilesize = 64;
    show-recents = false;
    mru-spaces = false;
    static-only = true;
    show-process-indicators = true;
    showhidden = true;
    expose-group-apps = true;
    appswitcher-all-displays = false;
    persistent-apps = [ "/Applications/Zed.app" ];
  };

  # Finder
  system.defaults.finder = {
    AppleShowAllExtensions = true;
    AppleShowAllFiles = true;
    ShowPathbar = true;
    ShowStatusBar = true;
    FXEnableExtensionChangeWarning = false;
    FXPreferredViewStyle = "clmv";
    QuitMenuItem = true;
    _FXShowPosixPathInTitle = true;
    FXDefaultSearchScope = "SCcf";
  };

  # Trackpad
  system.defaults.trackpad = {
    Clicking = true;
    Dragging = true;
    DragLock = true;
    TrackpadThreeFingerDrag = false;
  };

  # Scroll direction: natural for trackpad, traditional for mouse
  system.defaults.NSGlobalDomain."com.apple.swipescrolldirection" = true;

  # Cursor tracking speeds (0.0–3.0)
  system.defaults.NSGlobalDomain."com.apple.trackpad.scaling" = 1.5;

  system.defaults.NSGlobalDomain."com.apple.mouse.tapBehavior" = 1;
  system.defaults.NSGlobalDomain.NSWindowShouldDragOnGesture = true;
  # system.defaults.NSGlobalDomain._HIHideMenuBar = true;

  # Restart SystemUIServer so _HIHideMenuBar takes effect on Tahoe (26+).
  # Also kick the user launch agents that apply wallpaper and default-app preferences.
  system.activationScripts.postActivation.text = ''
    killall -qu ${config.system.primaryUser} SystemUIServer || true

    uid="$(id -u ${config.system.primaryUser} 2>/dev/null || true)"
    if [ -n "$uid" ]; then
      launchctl kickstart -k "gui/$uid/com.iceice666.default-apps" || true
      launchctl kickstart -k "gui/$uid/com.iceice666.wallpaper-refresh" || true
      # Mouse cursor tracking speed (not a typed nix-darwin option)
      launchctl asuser "$uid" defaults write NSGlobalDomain com.apple.mouse.scaling -float 2.5
    fi
  '';

  # Bluetooth trackpad (It only costs you NT$3,790! Why don't you get one?)
  system.defaults.CustomUserPreferences = {
    "com.apple.HIToolbox" = {
      AppleEnabledInputSources = squirrelTraditionalInputSources;
      AppleInputSourceHistory = squirrelTraditionalInputSources;
      AppleSelectedInputSources = squirrelTraditionalInputSources;
    };

    # Mos: reverse mouse scroll so trackpad=natural, mouse=traditional
    "com.caldis.Mos" = {
      reverse = true;
      smooth = true;
      autoLaunch = true;
      hideStatusBar = false;
      speed = 1;
      gap = 50;
    };

    "com.apple.driver.AppleBluetoothMultitouch.trackpad" = {
      Clicking = true;
      Dragging = true;
      DragLock = true;
      TrackpadThreeFingerDrag = false;
    };

  };

  # Touch ID for sudo
  security.pam.services.sudo_local.touchIdAuth = true;

  # Disable automatic macOS updates
  system.defaults.SoftwareUpdate.AutomaticallyInstallMacOSUpdates = false;
}
