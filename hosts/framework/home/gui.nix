{
  config,
  lib,
  pkgs,
  themegenCache,
  unstablePkgs,
  avatarImage ? null,
  desktopWallpaper,
  ewwNotificationMarkRead,
  ewwNotificationMarkUnread,
  ewwReload,
  ewwState,
  ewwStateConfig,
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
  makoPkg = unstablePkgs.mako;
  niriScratchpadHelper = pkgs.niri-scratchpad-helper;

  frameworkDarkman = pkgs.darkman.overrideAttrs (oldAttrs: {
    patches = (oldAttrs.patches or [ ]) ++ [
      (pkgs.writeText "darkman-framework-transition-offset.patch" ''
        diff --git a/scheduler.go b/scheduler.go
        index 631f6e1..8e7f0dc 100644
        --- a/scheduler.go
        +++ b/scheduler.go
        @@ -23,6 +23,9 @@ func SunriseAndSundown(loc geoclue.Location, now time.Time) (sunrise time.Time,
         
         	sundown, err = astral.Sunset(obs, now)
        +	sunrise = sunrise.Add(30 * time.Minute)
        +	sundown = sundown.Add(-30 * time.Minute)
        +
         	return
         }
      '')
    ];
  });

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

  suspendThenHibernateOnBattery = pkgs.writeShellScript "suspend-then-hibernate-on-battery" ''
    for supply in /sys/class/power_supply/*; do
      [ -d "$supply" ] || continue

      if [ "$(cat "$supply/type" 2>/dev/null || true)" = "Mains" ] \
        && [ "$(cat "$supply/online" 2>/dev/null || true)" = "1" ]; then
        exit 0
      fi
    done

    exec ${pkgs.systemd}/bin/systemctl suspend-then-hibernate
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

  workspacePathFromFocusedWorkspace = ''
    workspace_json="$(niri msg -j workspaces 2>/dev/null || printf '[]')"
    workspace_name="$(
      jq -r 'first(.[]? | select(.is_focused // .focused // false) | .name // empty) // empty' \
        <<< "$workspace_json"
    )"

    [ -n "$workspace_name" ] || exit 0

    case "$workspace_name" in
      \~)
        workspace_path="$HOME"
        ;;
      \~/*)
        workspace_path="$HOME/''${workspace_name#\~/}"
        ;;
      /*)
        workspace_path="$workspace_name"
        ;;
      *)
        workspace_path="$HOME/$workspace_name"
        ;;
    esac

    workspace_path="$(realpath -e "$workspace_path" 2>/dev/null)" || exit 0
    if [ ! -d "$workspace_path" ]; then
      workspace_path="$(dirname "$workspace_path")"
    fi
  '';

  lazygitRepoFromWorkspace = ''
    ${workspacePathFromFocusedWorkspace}

    repo="$(git -C "$workspace_path" rev-parse --show-toplevel 2>/dev/null)" || exit 0
    repo_hash="$(printf '%s' "$repo" | sha256sum | cut -c1-16)"
    app_id="dev.iceice666.lazygit.repo$repo_hash"
  '';

  spawnLazygit = pkgs.writeShellApplication {
    name = "spawn-niri-lazygit";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.git
      pkgs.ghostty
      pkgs.jq
      pkgs.lazygit
      niriPkg
    ];
    text = ''
      ${lazygitRepoFromWorkspace}

      exec ghostty \
        "--class=$app_id" \
        "--confirm-close-surface=false" \
        "--title=lazygit: $repo" \
        "--working-directory=$repo" \
        -e lazygit
    '';
  };

  toggleLazygit = pkgs.writeShellApplication {
    name = "toggle-niri-lazygit";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.git
      pkgs.jq
      niriPkg
      niriScratchpadHelper
    ];
    text = ''
      ${lazygitRepoFromWorkspace}

      workspace_id="$(
        jq -r 'first(.[]? | select(.is_focused // .focused // false) | .id // empty) // empty' \
          <<< "$workspace_json"
      )"

      [ -n "$workspace_id" ] || exit 0

      resize_lazygit_window() {
        niri msg action set-window-width --id "$1" "90%" || true
        niri msg action set-window-height --id "$1" "89%" || true
        sleep 0.1
        niri msg action center-window --id "$1" || true
        sleep 0.1
        niri msg action center-window --id "$1" || true
      }

      lazygit_window_on_focused_workspace() {
        windows="$(niri msg -j windows 2>/dev/null || printf '[]')"
        jq -r --arg app_id "$app_id" --arg workspace_id "$workspace_id" '
          first(
            .[]?
            | select(.app_id == $app_id)
            | select(((.workspace_id // .workspace // "") | tostring) == $workspace_id)
            | .id
          ) // empty
        ' <<< "$windows"
      }

      focused_lazygit_window() {
        windows="$(niri msg -j windows 2>/dev/null || printf '[]')"
        jq -r --arg app_id "$app_id" '
          first(
            .[]?
            | select(.app_id == $app_id)
            | select(.is_focused // .focused // false)
            | .id
          ) // empty
        ' <<< "$windows"
      }

      visible_window_id="$(lazygit_window_on_focused_workspace)"
      NS_WORKSPACE=scratch nscratch -id "$app_id" -s "${spawnLazygit}/bin/spawn-niri-lazygit" -m
      [ -z "$visible_window_id" ] || exit 0

      for _ in $(seq 1 40); do
        sleep 0.05

        window_id="$(focused_lazygit_window)"
        if [ -n "$window_id" ]; then
          resize_lazygit_window "$window_id"
          exit 0
        fi
      done
    '';
  };

  runJustRecipe = pkgs.writeShellApplication {
    name = "run-niri-just-recipe";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.fuzzel
      pkgs.ghostty
      pkgs.jq
      unstablePkgs.just
      niriPkg
    ];
    text = ''
      ${workspacePathFromFocusedWorkspace}

      justfile_json="$(
        cd "$workspace_path" && just --dump --dump-format json 2>/dev/null
      )" || exit 0

      justfile="$(
        jq -r '.source // empty' <<< "$justfile_json"
      )"
      [ -n "$justfile" ] || exit 0
      [ -f "$justfile" ] || exit 0

      just_dir="$(dirname "$justfile")"
      recipe_order="$(
        just --justfile "$justfile" --working-directory "$just_dir" --summary --unsorted 2>/dev/null
      )" || exit 0
      [ -n "$recipe_order" ] || exit 0

      recipes="$(
        jq -r --arg recipe_order "$recipe_order" '
          ($recipe_order | split(" ") | map(select(length > 0)))[] as $recipe_name
          | (.recipes[$recipe_name] // empty) as $recipe
          | select($recipe.private | not)
          | "\($recipe.namepath // $recipe_name)\t\($recipe.doc // "")"
        ' <<< "$justfile_json"
      )" || exit 0
      [ -n "$recipes" ] || exit 0

      selection="$(
        printf '%s\n' "$recipes" \
          | fuzzel --dmenu --no-sort --prompt "Just: "
      )" || exit 0

      [ -n "$selection" ] || exit 0
      recipe="''${selection%%$'\t'*}"
      [ -n "$recipe" ] || exit 0

      exec ghostty \
        "--title=just $recipe: $just_dir" \
        "--working-directory=$just_dir" \
        -e just --justfile "$justfile" --working-directory "$just_dir" "$recipe"
    '';
  };

  clipboardManager = pkgs.writeShellScript "framework-clipboard-manager" ''
    selection="$(
      ${pkgs.cliphist}/bin/cliphist list \
        | ${pkgs.fuzzel}/bin/fuzzel --dmenu --prompt "Clipboard: "
    )" || exit 0

    [ -n "$selection" ] || exit 0

    printf '%s' "$selection" \
      | ${pkgs.cliphist}/bin/cliphist decode \
      | ${pkgs.wl-clipboard}/bin/wl-copy
  '';

  frameworkPortalEnv = {
    XDG_DATA_DIRS = "${config.home.profileDirectory}/share:/nix/var/nix/profiles/default/share:/usr/local/share:/usr/share";
    NIX_XDG_DESKTOP_PORTAL_DIR = "${config.home.profileDirectory}/share/xdg-desktop-portal/portals";
    XDG_CURRENT_DESKTOP = "niri";
    XDG_SESSION_DESKTOP = "niri";
    XDG_SESSION_TYPE = "wayland";
  };

  frameworkSessionEnvironmentNames = [
    "GLFW_IM_MODULE"
    "NIX_XDG_DESKTOP_PORTAL_DIR"
    "QT_PLUGIN_PATH"
    "SDL_IM_MODULE"
    "XDG_CURRENT_DESKTOP"
    "XDG_DATA_DIRS"
    "XDG_SESSION_DESKTOP"
    "XDG_SESSION_TYPE"
    "XMODIFIERS"
  ];

  frameworkSessionEnvironmentList = lib.concatStringsSep " " frameworkSessionEnvironmentNames;

  gsettingsSchemaDataDir = "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}";

  cursorThemeName = "Bibata-Modern-Classic";
  cursorThemeSize = 24;

  themegenGtkTheme = pkgs.runCommand "themegen-gtk-theme" { } ''
    install_theme() {
      local name=$1
      local mode=$2
      local gtk3_base=$3
      local gtk4_base=$4
      local theme_dir="$out/share/themes/$name"

      mkdir -p "$theme_dir/gtk-3.0" "$theme_dir/gtk-4.0"

      {
        printf '[X-GNOME-Metatheme]\n'
        printf 'Name=%s\n' "$name"
        printf 'Type=X-GNOME-Metatheme\n'
        printf 'Comment=Wallpaper-derived Themegen GTK theme\n'
        printf 'Encoding=UTF-8\n'
        printf 'GtkTheme=%s\n' "$name"
        printf 'IconTheme=Papirus\n'
        printf 'CursorTheme=${cursorThemeName}\n'
        printf 'CursorSize=${toString cursorThemeSize}\n'
      } > "$theme_dir/index.theme"

      {
        printf '@import url("%s");\n\n' "$gtk3_base"
        cat "${themegenCache}/.config/gtk-3.0/themegen-$mode.css"
      } > "$theme_dir/gtk-3.0/gtk.css"

      {
        printf '@import url("%s");\n\n' "$gtk4_base"
        cat "${themegenCache}/.config/gtk-4.0/themegen-$mode.css"
      } > "$theme_dir/gtk-4.0/gtk.css"
    }

    install_theme \
      Themegen \
      light \
      resource:///org/gtk/libgtk/theme/Adwaita/gtk-contained.css \
      resource:///org/gtk/libgtk/theme/Default/Default-light.css

    install_theme \
      Themegen-dark \
      dark \
      resource:///org/gtk/libgtk/theme/Adwaita/gtk-contained-dark.css \
      resource:///org/gtk/libgtk/theme/Default/Default-dark.css
  '';

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
    mkdir -p "$HOME/.config/eww" "$HOME/.config/fuzzel" "$HOME/.config/qt5ct/colors" "$HOME/.config/qt6ct/colors"
    ln -sfn "theme-${mode}.scss" "$HOME/.config/eww/theme.scss"
    ln -sfn "themegen-${mode}.ini" "$HOME/.config/fuzzel/fuzzel.ini"
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
        systemctl --user import-environment ${frameworkSessionEnvironmentList}
        dbus-update-activation-environment --systemd ${frameworkSessionEnvironmentList}
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
        "@clipboardManager@"
        "@equibop@"
        "@ewwState@"
        "@ewwStateConfig@"
        "@fuzzel@"
        "@ghostty@"
        "@grim@"
        "@nautilus@"
        "@renameWorkspace@"
        "@runJustRecipe@"
        "@toggleLazygit@"
        "@slurp@"
        "@swaylock@"
        "@swappy@"
        "@zen@"
      ]
      [
        "${pkgs.brightnessctl}/bin/brightnessctl"
        (toString clipboardManager)
        (lib.getExe pkgs.equibop-bin)
        ewwState
        (toString ewwStateConfig)
        "${pkgs.fuzzel}/bin/fuzzel"
        "${pkgs.ghostty}/bin/ghostty"
        "${pkgs.grim}/bin/grim"
        "${pkgs.nautilus}/bin/nautilus"
        (toString renameWorkspace)
        "${runJustRecipe}/bin/run-niri-just-recipe"
        "${toggleLazygit}/bin/toggle-niri-lazygit"
        "${pkgs.slurp}/bin/slurp"
        "${pkgs.swaylock}/bin/swaylock"
        "${pkgs.swappy}/bin/swappy"
        (lib.getExe pkgs.zen-bin)
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

  systemd.user.services.cliphist = {
    Unit = {
      Description = "Clipboard history daemon";
      PartOf = [ "graphical-session.target" ];
      After = [
        "niri.service"
        "graphical-session.target"
      ];
      Wants = [ "graphical-session.target" ];
    };

    Service = {
      Type = "simple";
      ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --watch ${pkgs.cliphist}/bin/cliphist store";
      Restart = "on-failure";
      RestartSec = 2;
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  systemd.user.services.tailscale-systray = {
    Unit = {
      Description = "Tailscale system tray";
      Documentation = [ "https://tailscale.com/docs/features/client/linux-systray" ];
      ConditionEnvironment = [ "WAYLAND_DISPLAY" ];
      PartOf = [ "graphical-session.target" ];
      After = [
        "framework-eww.service"
        "niri.service"
        "graphical-session.target"
      ];
      Wants = [
        "framework-eww.service"
        "graphical-session.target"
      ];
    };

    Service = {
      Type = "simple";
      ExecStart = "${pkgs.tailscale}/bin/tailscale systray";
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
    cliphist
    ghostty
    grim
    imv
    unstablePkgs.librepods
    jq
    libnotify
    lm_sensors
    mpv
    nautilus
    niriScratchpadHelper
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
      name = "Themegen-dark";
      package = themegenGtkTheme;
    };
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
    gtk-theme = "Themegen-dark";
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

          ${pkgs.systemd}/bin/systemctl --user import-environment ${frameworkSessionEnvironmentList}
          ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd ${frameworkSessionEnvironmentList}
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
          gtkTheme = "Themegen";
          iconTheme = "Papirus-Light";
          mode = "light";
        }}
        ;;
      dark)
        ${setAppearance {
          colorScheme = "prefer-dark";
          gtkTheme = "Themegen-dark";
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
      package = frameworkDarkman;
      settings = {
        lat = 25.0;
        lng = 121.5;
        usegeoclue = false;
        dbusserver = true;
      };
      darkModeScripts.gtk = setAppearance {
        colorScheme = "prefer-dark";
        gtkTheme = "Themegen-dark";
        iconTheme = "Papirus-Dark";
        mode = "dark";
      };
      lightModeScripts.gtk = setAppearance {
        colorScheme = "default";
        gtkTheme = "Themegen";
        iconTheme = "Papirus-Light";
        mode = "light";
      };
    };
    gnome-keyring.enable = true;
    network-manager-applet.enable = true;

    mako = {
      enable = true;
      package = makoPkg;
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
        on-button-left = "exec ${ewwNotificationMarkRead} \"$id\"; ${makoPkg}/bin/makoctl invoke -n \"$id\"";
        on-button-right = "exec ${ewwNotificationMarkRead} \"$id\"; ${makoPkg}/bin/makoctl dismiss --no-history -n \"$id\"";
        on-notify = "exec ${ewwNotificationMarkUnread} \"$id\"";
        on-touch = "exec ${ewwNotificationMarkRead} \"$id\"; ${makoPkg}/bin/makoctl dismiss --no-history -n \"$id\"";
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
        {
          timeout = 1200;
          command = "${suspendThenHibernateOnBattery}";
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
