{
  config,
  lib,
  pkgs,
  unstablePkgs,
  avatarImage ? null,
  desktopWallpaper,
  ewwNotificationMarkRead,
  ewwNotificationMarkUnread,
  ewwPoll,
  ewwReload,
  ...
}:

let
  frameworkGraphicsEnv = ''
    if [ -d /run/opengl-driver/lib/dri ]; then
      export LIBGL_DRIVERS_PATH="/run/opengl-driver/lib/dri''${LIBGL_DRIVERS_PATH:+:''${LIBGL_DRIVERS_PATH}}"
    fi

    if [ -d /usr/lib/dri ]; then
      export LIBGL_DRIVERS_PATH="''${LIBGL_DRIVERS_PATH:+''${LIBGL_DRIVERS_PATH}:}/usr/lib/dri"
    fi

    if [ -d /run/opengl-driver/lib/gbm ]; then
      export GBM_BACKENDS_PATH="/run/opengl-driver/lib/gbm''${GBM_BACKENDS_PATH:+:''${GBM_BACKENDS_PATH}}"
    fi

    if [ -d /usr/lib/gbm ]; then
      export GBM_BACKENDS_PATH="''${GBM_BACKENDS_PATH:+''${GBM_BACKENDS_PATH}:}/usr/lib/gbm"
    fi

    if [ -d /run/opengl-driver/share/glvnd/egl_vendor.d ]; then
      export __EGL_VENDOR_LIBRARY_DIRS="/run/opengl-driver/share/glvnd/egl_vendor.d''${__EGL_VENDOR_LIBRARY_DIRS:+:''${__EGL_VENDOR_LIBRARY_DIRS}}"
    fi

    if [ -d /usr/share/glvnd/egl_vendor.d ]; then
      export __EGL_VENDOR_LIBRARY_DIRS="''${__EGL_VENDOR_LIBRARY_DIRS:+''${__EGL_VENDOR_LIBRARY_DIRS}:}/usr/share/glvnd/egl_vendor.d"
    fi

    if [ -d /run/opengl-driver/lib ]; then
      export LD_LIBRARY_PATH="/run/opengl-driver/lib''${LD_LIBRARY_PATH:+:''${LD_LIBRARY_PATH}}"
    fi

    if [ -d /usr/lib ]; then
      export LD_LIBRARY_PATH="''${LD_LIBRARY_PATH:+''${LD_LIBRARY_PATH}:}/usr/lib"
    fi
  '';

  niriPkg = unstablePkgs.niri;

  frameworkNiri = pkgs.writeShellScript "framework-niri" ''
    ${frameworkGraphicsEnv}
    exec ${niriPkg}/bin/niri "$@"
  '';

  frameworkNiriSession = pkgs.writeShellScript "framework-niri-session" ''
    ${frameworkGraphicsEnv}
    exec ${niriPkg}/bin/niri-session "$@"
  '';

  frameworkNiriDesktop = pkgs.writeText "framework-niri.desktop" ''
    [Desktop Entry]
    Name=Niri
    Comment=A scrollable-tiling Wayland compositor
    Exec=${frameworkNiriSession}
    Type=Application
    DesktopNames=niri
  '';

  frameworkNiriService = pkgs.writeText "framework-niri.service" ''
    [Unit]
    Description=A scrollable-tiling Wayland compositor
    BindsTo=graphical-session.target
    Before=graphical-session.target
    Wants=graphical-session-pre.target
    After=graphical-session-pre.target

    Wants=xdg-desktop-autostart.target
    Before=xdg-desktop-autostart.target

    [Service]
    Slice=session.slice
    Type=notify
    ExecStart=${frameworkNiri} --session
  '';

  renameWorkspace = pkgs.writeShellScript "rename-niri-workspace" ''
    current_name="$(
        ${niriPkg}/bin/niri msg -j workspaces 2>/dev/null \
        | ${pkgs.jq}/bin/jq -r 'first(.[]? | select(.is_focused // .focused // false) | .name // empty) // empty'
    )"

    name="$(
      printf '%s\n' "$current_name" \
        | ${pkgs.fuzzel}/bin/fuzzel --dmenu --prompt "Workspace name: "
    )" || exit 0

    if [ -n "$name" ]; then
      ${niriPkg}/bin/niri msg action set-workspace-name "$name"
    else
      ${niriPkg}/bin/niri msg action unset-workspace-name
    fi
  '';

  frameworkPortalEnv = {
    XDG_DATA_DIRS = "${config.home.profileDirectory}/share:/nix/var/nix/profiles/default/share:/usr/local/share:/usr/share";
    NIX_XDG_DESKTOP_PORTAL_DIR = "${config.home.profileDirectory}/share/xdg-desktop-portal/portals";
    XDG_CURRENT_DESKTOP = "niri";
    XDG_SESSION_DESKTOP = "niri";
    XDG_SESSION_TYPE = "wayland";
  };

  gsettingsSchemaDataDir = "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}";

  cursorThemeName = "Bibata-Modern-Classic";
  cursorThemeSize = 24;

  mkQtctConfig =
    {
      iconTheme,
      mode,
      version,
    }:
    pkgs.writeText "themegen-qt${version}ct-${mode}.conf" ''
      [Appearance]
      color_scheme_path=${config.xdg.configHome}/qt${version}ct/colors/themegen.conf
      custom_palette=true
      icon_theme=${iconTheme}
      standard_dialogs=xdgdesktopportal
      style=Fusion
    '';

  installThemegenAppearance = mode: ''
    mkdir -p "$HOME/.config/eww" "$HOME/.config/fuzzel" "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0" "$HOME/.config/qt5ct/colors" "$HOME/.config/qt6ct/colors"
    ln -sfn "theme-${mode}.scss" "$HOME/.config/eww/theme.scss"
    ln -sfn "themegen-${mode}.ini" "$HOME/.config/fuzzel/fuzzel.ini"
    ln -sfn "themegen-${mode}.css" "$HOME/.config/gtk-3.0/themegen.css"
    ln -sfn "themegen-${mode}.css" "$HOME/.config/gtk-4.0/themegen.css"
    ln -sfn "themegen-${mode}.conf" "$HOME/.config/qt5ct/colors/themegen.conf"
    ln -sfn "themegen-${mode}.conf" "$HOME/.config/qt6ct/colors/themegen.conf"
    ln -sfn "qt5ct-${mode}.conf" "$HOME/.config/qt5ct/qt5ct.conf"
    ln -sfn "qt6ct-${mode}.conf" "$HOME/.config/qt6ct/qt6ct.conf"
  '';

  setAppearance =
    {
      colorScheme,
      gtkTheme,
      iconTheme,
      mode,
    }:
    ''
      ${installThemegenAppearance mode}

      export XDG_DATA_DIRS=${lib.escapeShellArg gsettingsSchemaDataDir}''${XDG_DATA_DIRS:+:''${XDG_DATA_DIRS}}

      ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface color-scheme ${lib.escapeShellArg colorScheme}
      ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface gtk-theme ${lib.escapeShellArg gtkTheme}
      ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface icon-theme ${lib.escapeShellArg iconTheme}
      ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface cursor-theme ${lib.escapeShellArg cursorThemeName}
      ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface cursor-size ${toString cursorThemeSize}

      ${pkgs.systemd}/bin/systemctl --user try-restart blueman-applet.service network-manager-applet.service >/dev/null 2>&1 || true
      ${ewwReload}
    '';

  frameworkPostSwitch = pkgs.writeShellApplication {
    name = "framework-post-switch";
    runtimeInputs = with pkgs; [
      dbus
      systemd
    ];
    text = ''
      if [[ "$(uname -s)" != "Linux" ]]; then
        echo "This helper is only for the Framework Arch Linux host." >&2
        exit 1
      fi

      hm_session_vars="$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
      if [ -r "$hm_session_vars" ]; then
        unset __HM_SESS_VARS_SOURCED
        set +u
        # shellcheck source=/dev/null
        . "$hm_session_vars"
        set -u
      fi

      case ":''${XDG_DATA_DIRS:-}:" in
        *:/usr/share:*) ;;
        *)
          export XDG_DATA_DIRS="''${XDG_DATA_DIRS:+''${XDG_DATA_DIRS}:}/usr/local/share:/usr/share"
          ;;
      esac

      if systemctl --user show-environment >/dev/null 2>&1; then
        systemctl --user daemon-reload
        systemctl --user import-environment XDG_DATA_DIRS NIX_XDG_DESKTOP_PORTAL_DIR XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE
        dbus-update-activation-environment --systemd XDG_DATA_DIRS NIX_XDG_DESKTOP_PORTAL_DIR XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE
        systemctl --user start xdg-document-portal.service xdg-permission-store.service || true
        systemctl --user restart xdg-desktop-portal.service || true
        systemctl --user enable --now pipewire.service pipewire-pulse.service wireplumber.service || true
      else
        cat >&2 <<'EOF'
      User systemd is not available in this shell.
      After logging into a normal user session, run:
        systemctl --user start xdg-document-portal.service xdg-permission-store.service
        systemctl --user restart xdg-desktop-portal.service
        systemctl --user enable --now pipewire.service pipewire-pulse.service wireplumber.service
      EOF
      fi

    '';
  };

  niriConfig =
    builtins.replaceStrings
      [
        "@brightnessctl@"
        "@bash@"
        "@codium@"
        "@ewwPoll@"
        "@fuzzel@"
        "@ghostty@"
        "@grim@"
        "@nautilus@"
        "@playerctl@"
        "@renameWorkspace@"
        "@slurp@"
        "@swaylock@"
        "@swappy@"
        "@wpctl@"
        "@zed@"
      ]
      [
        "${pkgs.brightnessctl}/bin/brightnessctl"
        "${pkgs.bash}/bin/bash"
        "${pkgs.vscodium}/bin/codium"
        (toString ewwPoll)
        "${pkgs.fuzzel}/bin/fuzzel"
        "${pkgs.ghostty}/bin/ghostty"
        "${pkgs.grim}/bin/grim"
        "${pkgs.nautilus}/bin/nautilus"
        "${pkgs.playerctl}/bin/playerctl"
        (toString renameWorkspace)
        "${pkgs.slurp}/bin/slurp"
        "${pkgs.swaylock}/bin/swaylock"
        "${pkgs.swappy}/bin/swappy"
        "${pkgs.wireplumber}/bin/wpctl"
        (lib.getExe unstablePkgs.zed-editor)
      ]
      (builtins.readFile ./niri-config.kdl);
in
{
  imports = [ ./eww ];

  systemd.user.services.swaybg = {
    Unit = {
      Description = "Swaybg wallpaper daemon";
      PartOf = [ "graphical-session.target" ];
      After = [
        "niri.service"
        "graphical-session.target"
      ];
      Wants = [ "graphical-session.target" ];
    };

    Service = {
      Type = "simple";
      ExecStart = "${pkgs.swaybg}/bin/swaybg -i ${lib.escapeShellArg (toString desktopWallpaper)} -m fill";
      Restart = "on-failure";
      RestartSec = 2;
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  home.packages = with pkgs; [
    frameworkPostSwitch
    adwaita-icon-theme
    brightnessctl
    bc
    ghostty
    grim
    imv
    jq
    libnotify
    lm_sensors
    mpv
    nautilus
    cascadia-code
    noto-fonts
    noto-fonts-color-emoji
    overskride
    papirus-icon-theme
    bibata-cursors
    pciutils
    pavucontrol
    playerctl
    procps
    socat
    slurp
    swappy
    swaybg
    wev
    wf-recorder
    wl-clipboard
    wlr-randr
    xwayland-satellite
    xdg-desktop-portal-gnome
    xdg-desktop-portal-gtk
  ];

  fonts.fontconfig.enable = true;

  home.pointerCursor = {
    enable = true;
    name = cursorThemeName;
    package = pkgs.bibata-cursors;
    size = cursorThemeSize;
    gtk.enable = true;
    x11.enable = true;
  };

  gtk = {
    enable = true;
    cursorTheme = {
      name = cursorThemeName;
      package = pkgs.bibata-cursors;
      size = cursorThemeSize;
    };
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
    gtk3.extraCss = ''
      @import url("themegen.css");
    '';
    gtk4.extraCss = ''
      @import url("themegen.css");
    '';
  };

  qt = {
    enable = true;
    platformTheme.name = "qtct";
    style.name = "Fusion";
  };

  home.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    QT_QPA_PLATFORM = "wayland;xcb";
    XDG_CURRENT_DESKTOP = "niri";
    XDG_SESSION_DESKTOP = "niri";
    XDG_SESSION_TYPE = "wayland";
  };

  dconf.settings."org/gnome/desktop/interface" = {
    color-scheme = "prefer-dark";
    cursor-size = cursorThemeSize;
    cursor-theme = cursorThemeName;
    gtk-theme = "Adwaita-dark";
    icon-theme = "Papirus-Dark";
  };

  home.activation.frameworkPortalEnvironment =
    lib.hm.dag.entryBetween [ "dconfSettings" ] [ "installPackages" ]
      ''
        if ${pkgs.systemd}/bin/systemctl --user show-environment >/dev/null 2>&1; then
          export XDG_DATA_DIRS=${lib.escapeShellArg frameworkPortalEnv.XDG_DATA_DIRS}
          export NIX_XDG_DESKTOP_PORTAL_DIR=${lib.escapeShellArg frameworkPortalEnv.NIX_XDG_DESKTOP_PORTAL_DIR}
          export XDG_CURRENT_DESKTOP=${lib.escapeShellArg frameworkPortalEnv.XDG_CURRENT_DESKTOP}
          export XDG_SESSION_DESKTOP=${lib.escapeShellArg frameworkPortalEnv.XDG_SESSION_DESKTOP}
          export XDG_SESSION_TYPE=${lib.escapeShellArg frameworkPortalEnv.XDG_SESSION_TYPE}

          ${pkgs.systemd}/bin/systemctl --user import-environment XDG_DATA_DIRS NIX_XDG_DESKTOP_PORTAL_DIR XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE
          ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd XDG_DATA_DIRS NIX_XDG_DESKTOP_PORTAL_DIR XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE
          ${pkgs.systemd}/bin/systemctl --user reset-failed xdg-desktop-portal.service xdg-document-portal.service || true
          ${pkgs.systemd}/bin/systemctl --user start xdg-document-portal.service xdg-permission-store.service || true
          ${pkgs.systemd}/bin/systemctl --user restart xdg-desktop-portal.service || true
        fi
      '';

  home.activation.frameworkThemegenAppearance = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    mode="$(${pkgs.darkman}/bin/darkman get 2>/dev/null || true)"
    case "$mode" in
      light|dark) ;;
      *) mode="dark" ;;
    esac

    case "$mode" in
      light)
        ${setAppearance {
          colorScheme = "default";
          gtkTheme = "Adwaita";
          iconTheme = "Papirus-Light";
          mode = "light";
        }}
        ;;
      dark)
        ${setAppearance {
          colorScheme = "prefer-dark";
          gtkTheme = "Adwaita-dark";
          iconTheme = "Papirus-Dark";
          mode = "dark";
        }}
        ;;
    esac

    ${ewwReload}
  '';

  xdg = {
    enable = true;

    dataFile = {
      "wayland-sessions/niri.desktop".source = frameworkNiriDesktop;
      "systemd/user/niri.service".source = frameworkNiriService;
      "systemd/user/niri-shutdown.target".source = "${niriPkg}/share/systemd/user/niri-shutdown.target";
    };

    portal = {
      enable = true;
      configPackages = [ niriPkg ];
      config.common = {
        default = [
          "gnome"
          "gtk"
        ];
        "org.freedesktop.impl.portal.Settings" = "gnome";
      };
      config.niri = {
        default = [
          "gnome"
          "gtk"
        ];
        "org.freedesktop.impl.portal.Access" = "gtk";
        "org.freedesktop.impl.portal.Notification" = "gtk";
        "org.freedesktop.impl.portal.ScreenCast" = "gnome";
        "org.freedesktop.impl.portal.Screenshot" = "gnome";
        "org.freedesktop.impl.portal.Secret" = "gnome-keyring";
        "org.freedesktop.impl.portal.Settings" = "gnome";
      };
      extraPortals = [
        pkgs.xdg-desktop-portal-gnome
        pkgs.xdg-desktop-portal-gtk
      ];
    };

    terminal-exec = {
      enable = true;
      settings.default = [ "com.mitchellh.ghostty.desktop" ];
    };
  };

  home.file.".config/niri/config.kdl".text = niriConfig;

  xdg.configFile = {
    "qt5ct/qt5ct-dark.conf".source = mkQtctConfig {
      iconTheme = "Papirus-Dark";
      mode = "dark";
      version = "5";
    };
    "qt5ct/qt5ct-light.conf".source = mkQtctConfig {
      iconTheme = "Papirus-Light";
      mode = "light";
      version = "5";
    };
    "qt6ct/qt6ct-dark.conf".source = mkQtctConfig {
      iconTheme = "Papirus-Dark";
      mode = "dark";
      version = "6";
    };
    "qt6ct/qt6ct-light.conf".source = mkQtctConfig {
      iconTheme = "Papirus-Light";
      mode = "light";
      version = "6";
    };
  };

  programs.fuzzel = {
    enable = true;
  };

  programs.swaylock = {
    enable = true;
    settings = {
      color = "171717";
      font = "Cascadia Code NF";
      indicator-radius = 120;
      indicator-thickness = 8;
      ring-color = "3b82f6";
      key-hl-color = "93c5fd";
      line-color = "00000000";
      inside-color = "171717cc";
      separator-color = "00000000";
    };
  };

  services = {
    blueman-applet.enable = true;
    darkman = {
      enable = true;
      settings = {
        lat = 25.0;
        lng = 121.5;
        usegeoclue = false;
        dbusserver = true;
      };
      darkModeScripts.gtk = setAppearance {
        colorScheme = "prefer-dark";
        gtkTheme = "Adwaita-dark";
        iconTheme = "Papirus-Dark";
        mode = "dark";
      };
      lightModeScripts.gtk = setAppearance {
        colorScheme = "default";
        gtkTheme = "Adwaita";
        iconTheme = "Papirus-Light";
        mode = "light";
      };
    };
    gnome-keyring.enable = true;
    network-manager-applet.enable = true;

    mako = {
      enable = true;
      settings = {
        anchor = "top-right";
        width = 360;
        height = 120;
        margin = "12";
        padding = "12";
        border-size = 2;
        border-radius = 8;
        background-color = "#171717f2";
        text-color = "#e5e5e5ff";
        border-color = "#60a5faff";
        default-timeout = 7000;
        font = "Noto Sans 12";
        max-history = 50;
        icons = true;
        max-icon-size = 24;
        on-button-left = "exec ${ewwNotificationMarkRead} \"$id\"; ${pkgs.mako}/bin/makoctl invoke -n \"$id\"";
        on-button-right = "exec ${ewwNotificationMarkRead} \"$id\"; ${pkgs.mako}/bin/makoctl dismiss --no-history -n \"$id\"";
        on-notify = "exec ${ewwNotificationMarkUnread} \"$id\"";
        on-touch = "exec ${ewwNotificationMarkRead} \"$id\"; ${pkgs.mako}/bin/makoctl dismiss --no-history -n \"$id\"";
      };
    };

    swayidle = {
      enable = true;
      timeouts = [
        {
          timeout = 300;
          command = "${pkgs.swaylock}/bin/swaylock -f";
        }
        {
          timeout = 600;
          command = "${niriPkg}/bin/niri msg action power-off-monitors";
          resumeCommand = "${niriPkg}/bin/niri msg action power-on-monitors";
        }
      ];
      events = [
        {
          event = "before-sleep";
          command = "${pkgs.swaylock}/bin/swaylock -f";
        }
      ];
    };
  };
}
