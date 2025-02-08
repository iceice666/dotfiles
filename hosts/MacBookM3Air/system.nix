{...}:
###################################################################################
#
#  macOS's System configuration
#
#  All the configuration options are documented here:
#    https://daiderd.com/nix-darwin/manual/index.html#sec-options
#
###################################################################################
{
  system = {
    stateVersion = 5;
    # activationScripts are executed every time you boot the system or run `nixos-rebuild` / `darwin-rebuild`.
    activationScripts.postUserActivation.text = ''
      # activateSettings -u will reload the settings from the database and apply them to the current session,
      # so we do not need to logout and login again to make the changes take effect.
      /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
    '';

    defaults = {
      menuExtraClock.Show24Hour = true; # show 24 hour clock

      # customize dock
      dock = {
        autohide = true;
        # disable recent apps
        show-recents = false;
        # Whether to automatically rearrange spaces based on most recent use.
        mru-spaces = false;
        # Scroll up on a Dock icon to show all Space's opened windows for an app, or open stack.
        scroll-to-open = true;
        # Only show opened apps in Dock.
        static-only = true;
        # Size of the icons in the dock.
        tilesize = 64;
      };

      # customize trackpad
      trackpad = {
        Clicking = true; # enable tap to click
        TrackpadRightClick = true; # enable two finger right click
        TrackpadThreeFingerDrag = true; # enable three finger drag
      };

      NSGlobalDomain = {
        # Whether to automatically switch between light and dark mode.
        AppleInterfaceStyleSwitchesAutomatically = true;
        # Whether to use centimeters (metric) or inches (US, UK) as the measurement unit.
        AppleMeasurementUnits = "Centimeters";
        # Whether to use the metric system.
        AppleMetricUnits = 1;
        # Jump to the spot that’s clicked on the scroll bar.
        AppleScrollerPagingBehavior = true;
        # Whether to show all file extensions in Finder.
        AppleShowAllExtensions = true;
        # Whether to always show hidden files.
        AppleShowAllFiles = true;
        # Whether to use Celsius or Fahrenheit.
        AppleTemperatureUnit = "Celsius";
        # Set when to start repeating key
        InitialKeyRepeat = 25;
        # Set how fast when repeat a key
        KeyRepeat = 2;
        # Choose whether the default file save location is on disk or iCloud
        NSDocumentSaveNewDocumentsToCloud = false;
        # Sets the level of font smoothing (sub-pixel font rendering).
        AppleFontSmoothing = 0;
      };

      finder = {
        # Whether to always show hidden files.
        AppleShowAllFiles = true;
        # Whether to show icons on the desktop or not.
        CreateDesktop = false;
        # Set the default search scope when performing a search
        FXDefaultSearchScope = "SCcf";
        # Whether to display a warning when changing a file extension.
        FXEnableExtensionChangeWarning = false;
        # Change the default finder view.
        FXPreferredViewStyle = "Nlsv";
        # Change the default folder shown in Finder windows.
        NewWindowTarget = "Home";
        # Show path breadcrumbs in finder windows.
        ShowPathbar = true;
        # Keep folders on top when sorting by name
        _FXSortFoldersFirst = true;
        # Whether to show the full POSIX filepath in the window title.
        _FXShowPosixPathInTitle = true;
      };

      # Hide widgets on desktop.
      WindowManager.StandardHideWidgets = true;

      # Customize settings that not supported by nix-darwin directly
      # see the source code of this project to get more undocumented options:
      #    https://github.com/rgcr/m-cli
      # Or this website: https://macos-defaults.com/
      #
      # All custom entries can be found by running `defaults read` command.
      # or `defaults read xxx` to read a specific domain.
      CustomUserPreferences = {
        "com.apple.desktopservices" = {
          # Avoid creating .DS_Store files on network or USB volumes
          DSDontWriteNetworkStores = true;
          DSDontWriteUSBStores = true;
        };

        "com.apple.screensaver" = {
          # Require password immediately after sleep or screen saver begins
          askForPassword = 1;
          askForPasswordDelay = 0;
        };

        "com.apple.universalaccess" = {
          showWindowTitlebarIcons = true;
        };
      };
    };
  };

  security = {
    # Add ability to used TouchID for sudo authentication
    pam.enableSudoTouchIdAuth = true;
  };
}
