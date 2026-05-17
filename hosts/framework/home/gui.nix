{
  config,
  lib,
  pkgs,
  avatarImage ? null,
  desktopWallpaper,
  ewwLaunch,
  ...
}:

let
  frameworkGpuSetup = lib.getExe config.targets.genericLinux.gpu.setupPackage;

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

  frameworkNiri = pkgs.writeShellScript "framework-niri" ''
    ${frameworkGraphicsEnv}
    exec ${pkgs.niri}/bin/niri "$@"
  '';

  frameworkNiriSession = pkgs.writeShellScript "framework-niri-session" ''
    ${frameworkGraphicsEnv}
    exec ${pkgs.niri}/bin/niri-session "$@"
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

  frameworkPortalEnv = {
    XDG_DATA_DIRS = "${config.home.profileDirectory}/share:/nix/var/nix/profiles/default/share:/usr/local/share:/usr/share";
    NIX_XDG_DESKTOP_PORTAL_DIR = "${config.home.profileDirectory}/share/xdg-desktop-portal/portals";
    XDG_CURRENT_DESKTOP = "niri";
    XDG_SESSION_DESKTOP = "niri";
    XDG_SESSION_TYPE = "wayland";
  };

  frameworkDbusServices = [
    "ca.desrt.dconf.service"
    "org.freedesktop.impl.portal.PermissionStore.service"
    "org.freedesktop.impl.portal.desktop.gnome.service"
    "org.freedesktop.impl.portal.desktop.gtk.service"
    "org.freedesktop.portal.Desktop.service"
    "org.freedesktop.portal.Documents.service"
  ];

  frameworkLoginUser = "iceice666";
  frameworkGreeterBackground = toString desktopWallpaper;
  frameworkGreeterAvatarSetup =
    if avatarImage == null then
      ""
    else
      ''
        sudo install -Dm0644 "${avatarImage}" "/var/lib/AccountsService/icons/${frameworkLoginUser}"
        printf '%s\n' \
          '[User]' \
          'Icon=/var/lib/AccountsService/icons/${frameworkLoginUser}' \
          'SystemAccount=false' \
          > "$accounts_user_temp"
        sudo install -Dm0600 "$accounts_user_temp" "/var/lib/AccountsService/users/${frameworkLoginUser}"
      '';

  frameworkRegreetConfig = pkgs.writeText "framework-regreet.toml" ''
    [background]
    path = "${frameworkGreeterBackground}"
    fit = "Cover"

    [GTK]
    application_prefer_dark_theme = true
    cursor_theme_name = "Adwaita"
    cursor_blink = true
    font_name = "Sans 13"
    icon_theme_name = "Adwaita"
    theme_name = "Adwaita"

    [commands]
    reboot = ["systemctl", "reboot"]
    poweroff = ["systemctl", "poweroff"]

    [appearance]
    greeting_msg = "${frameworkLoginUser}"

    [widget.clock]
    format = "%a %H:%M"
    resolution = "500ms"
    label_width = 150
  '';

  frameworkRegreetStyle = pkgs.writeText "framework-regreet.css" ''
    window {
      background: transparent;
    }

    box,
    grid {
      border-radius: 16px;
    }

    entry,
    button,
    combobox,
    menubutton {
      border-radius: 10px;
    }

    entry {
      background-color: rgba(23, 23, 23, 0.54);
      border-color: rgba(255, 214, 224, 0.32);
      color: #f8fafc;
    }

    entry:focus {
      background-color: rgba(23, 23, 23, 0.74);
      border-color: rgba(255, 214, 224, 0.86);
      box-shadow: 0 0 28px rgba(255, 214, 224, 0.34);
    }
  '';

  frameworkPostSwitch = pkgs.writeShellApplication {
    name = "framework-post-switch";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
    ];
    text = ''
      if [[ "$(uname -s)" != "Linux" ]]; then
        echo "This helper is only for the Framework Arch Linux host." >&2
        exit 1
      fi

      if ! command -v pacman >/dev/null 2>&1; then
        echo "pacman not found; this helper expects Arch Linux." >&2
        exit 1
      fi

      required_packages=(
        accountsservice
        cage
        fprintd
        greetd
        greetd-regreet
      )

      missing_packages=()
      for package in "''${required_packages[@]}"; do
        if ! pacman -Q "$package" >/dev/null 2>&1; then
          missing_packages+=("$package")
        fi
      done

      if ((''${#missing_packages[@]} > 0)); then
        echo "Missing Arch GUI packages: ''${missing_packages[*]}" >&2
        echo "Run 'just framework-bootstrap' before re-running this helper." >&2
        exit 1
      fi

      sudo -v
      sudo ${frameworkGpuSetup}

      niri_desktop_temp="$(mktemp)"
      greetd_config_temp="$(mktemp)"
      greetd_pam_temp="$(mktemp)"
      regreet_config_temp="$(mktemp)"
      regreet_style_temp="$(mktemp)"
      accounts_user_temp="$(mktemp)"
      trap 'rm -f "$niri_desktop_temp" "$greetd_config_temp" "$greetd_pam_temp" "$regreet_config_temp" "$regreet_style_temp" "$accounts_user_temp"' EXIT

      cp ${frameworkNiriDesktop} "$niri_desktop_temp"
      cp ${frameworkRegreetConfig} "$regreet_config_temp"
      cp ${frameworkRegreetStyle} "$regreet_style_temp"

      sudo install -Dm0644 "$niri_desktop_temp" /usr/share/wayland-sessions/niri.desktop
      sudo install -d -m0755 /etc/greetd/sessions
      sudo rm -f /etc/greetd/sessions/*.desktop
      sudo install -Dm0644 "$niri_desktop_temp" /etc/greetd/sessions/niri.desktop
      sudo install -Dm0644 "$regreet_config_temp" /etc/greetd/regreet.toml
      sudo install -Dm0644 "$regreet_style_temp" /etc/greetd/regreet.css

      ${frameworkGreeterAvatarSetup}

      printf '%s\n' \
        '[terminal]' \
        'vt = 1' \
        "" \
        '[default_session]' \
        'command = "env GTK_USE_PORTAL=0 GDK_DEBUG=no-portals dbus-run-session cage -s -mlast -- regreet --config /etc/greetd/regreet.toml --style /etc/greetd/regreet.css"' \
        'user = "greeter"' \
        > "$greetd_config_temp"
      sudo install -Dm0644 "$greetd_config_temp" /etc/greetd/config.toml

      if [ -f /etc/pam.d/greetd ] && ! grep -q '^auth[[:space:]].*pam_fprintd\.so' /etc/pam.d/greetd; then
        {
          printf '%s\n' 'auth sufficient pam_fprintd.so'
          cat /etc/pam.d/greetd
        } > "$greetd_pam_temp"
        sudo install -m0644 "$greetd_pam_temp" /etc/pam.d/greetd
      fi

      if systemctl is-enabled greetd.service >/dev/null 2>&1; then
        sudo systemctl start greetd.service
      else
        echo "greetd.service is not enabled; run 'just framework-bootstrap' to finish Arch system setup." >&2
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
        systemctl --user start xdg-document-portal.service xdg-permission-store.service xdg-desktop-portal.service
        systemctl --user enable --now pipewire.service pipewire-pulse.service wireplumber.service
      else
        cat >&2 <<'EOF'
      User systemd is not available in this shell.
      After logging into a normal user session, run:
        systemctl --user start xdg-document-portal.service xdg-permission-store.service xdg-desktop-portal.service
        systemctl --user enable --now pipewire.service pipewire-pulse.service wireplumber.service
      EOF
      fi
    '';
  };

  niriConfig =
    builtins.replaceStrings
      [
        "@bluemanApplet@"
        "@brightnessctl@"
        "@codium@"
        "@fuzzel@"
        "@ghostty@"
        "@grim@"
        "@wallpaper@"
        "@launchEww@"
        "@mako@"
        "@nautilus@"
        "@nmApplet@"
        "@niri@"
        "@playerctl@"
        "@slurp@"
        "@swaybg@"
        "@swayidle@"
        "@swaylock@"
        "@swappy@"
        "@wpctl@"
        "@zed@"
      ]
      [
        "${pkgs.blueman}/bin/blueman-applet"
        "${pkgs.brightnessctl}/bin/brightnessctl"
        "${pkgs.vscodium}/bin/codium"
        "${pkgs.fuzzel}/bin/fuzzel"
        "${pkgs.ghostty}/bin/ghostty"
        "${pkgs.grim}/bin/grim"
        (toString desktopWallpaper)
        (toString ewwLaunch)
        "${pkgs.mako}/bin/mako"
        "${pkgs.nautilus}/bin/nautilus"
        "${pkgs.networkmanagerapplet}/bin/nm-applet"
        "${frameworkNiri}"
        "${pkgs.playerctl}/bin/playerctl"
        "${pkgs.slurp}/bin/slurp"
        "${pkgs.swaybg}/bin/swaybg"
        "${pkgs.swayidle}/bin/swayidle"
        "${pkgs.swaylock}/bin/swaylock"
        "${pkgs.swappy}/bin/swappy"
        "${pkgs.wireplumber}/bin/wpctl"
        "${pkgs.zed-bin}/bin/zed"
      ]
      (builtins.readFile ./niri-config.kdl);
in
{
  imports = [ ./eww ];

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
    noto-fonts
    noto-fonts-color-emoji
    overskride
    papirus-icon-theme
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
    nerd-fonts.caskaydia-cove
  ];

  fonts.fontconfig.enable = true;

  gtk = {
    enable = true;
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
  };

  qt = {
    enable = true;
    platformTheme.name = "gtk";
    style.name = "adwaita-dark";
  };

  home.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    XDG_CURRENT_DESKTOP = "niri";
    XDG_SESSION_DESKTOP = "niri";
    XDG_SESSION_TYPE = "wayland";
  };

  home.activation.frameworkPortalEnvironment =
    lib.hm.dag.entryBetween [ "dconfSettings" ] [ "installPackages" ]
      ''
        dbus_service_dir="$HOME/.local/share/dbus-1/services"
        mkdir -p "$dbus_service_dir"
        ${lib.concatMapStringsSep "\n" (service: ''
          if [ -e /usr/share/dbus-1/services/${service} ]; then
            ln -sfn /usr/share/dbus-1/services/${service} "$dbus_service_dir/${service}"
          fi
        '') frameworkDbusServices}

        if ${pkgs.systemd}/bin/systemctl --user show-environment >/dev/null 2>&1; then
          export XDG_DATA_DIRS=${lib.escapeShellArg frameworkPortalEnv.XDG_DATA_DIRS}
          export NIX_XDG_DESKTOP_PORTAL_DIR=${lib.escapeShellArg frameworkPortalEnv.NIX_XDG_DESKTOP_PORTAL_DIR}
          export XDG_CURRENT_DESKTOP=${lib.escapeShellArg frameworkPortalEnv.XDG_CURRENT_DESKTOP}
          export XDG_SESSION_DESKTOP=${lib.escapeShellArg frameworkPortalEnv.XDG_SESSION_DESKTOP}
          export XDG_SESSION_TYPE=${lib.escapeShellArg frameworkPortalEnv.XDG_SESSION_TYPE}

          ${pkgs.systemd}/bin/systemctl --user import-environment XDG_DATA_DIRS NIX_XDG_DESKTOP_PORTAL_DIR XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE
          ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd XDG_DATA_DIRS NIX_XDG_DESKTOP_PORTAL_DIR XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE
          ${pkgs.systemd}/bin/systemctl --user reset-failed xdg-desktop-portal.service xdg-document-portal.service || true
          ${pkgs.systemd}/bin/systemctl --user start xdg-document-portal.service xdg-permission-store.service xdg-desktop-portal.service || true
        fi
      '';

  xdg = {
    enable = true;

    dataFile = {
      "wayland-sessions/niri.desktop".source = frameworkNiriDesktop;
      "systemd/user/niri.service".source = frameworkNiriService;
      "systemd/user/niri-shutdown.target".source = "${pkgs.niri}/share/systemd/user/niri-shutdown.target";
    };

    portal = {
      enable = true;
      configPackages = [ pkgs.niri ];
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

  programs.fuzzel = {
    enable = true;
    settings = {
      main = {
        terminal = "ghostty";
        layer = "overlay";
        width = 48;
        lines = 12;
        tabs = 4;
        font = "CaskaydiaCove Nerd Font:size=14";
        icon-theme = "Papirus-Dark";
      };
      colors = {
        background = "171717f2";
        text = "e5e5e5ff";
        match = "93c5fdff";
        selection = "334155ff";
        selection-text = "ffffffff";
        border = "60a5faff";
      };
      border = {
        width = 2;
        radius = 8;
      };
    };
  };

  programs.swaylock = {
    enable = true;
    settings = {
      color = "171717";
      font = "CaskaydiaCove Nerd Font";
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
        icons = true;
        max-icon-size = 48;
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
          command = "${pkgs.niri}/bin/niri msg action power-off-monitors";
          resumeCommand = "${pkgs.niri}/bin/niri msg action power-on-monitors";
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
