{
  config,
  lib,
  pkgs,
  desktopWallpapers,
  themegenWallpapers,
  themegenStateDir,
  themegenTargets,
  agsStylesFor,
  frameworkSetAppearance,
  ...
}:

let
  wallpaperIds = map (entry: entry.id) themegenWallpapers;
  cursorTheme = config.gtk.cursorTheme;

  # Everything one wallpaper needs at runtime: the themegen render plus
  # framework-only derived files (AGS CSS, GTK theme directories).
  mkBundle =
    entry:
    let
      agsStyles = agsStylesFor entry.cache;
    in
    pkgs.runCommand "framework-themegen-bundle-${entry.id}" { preferLocalBuild = true; } ''
      files="$out/files"
      mkdir -p "$files"
      cp -r ${entry.cache}/. "$files/"
      chmod -R u+w "$files"

      mkdir -p "$files/.config/ags"
      cp ${agsStyles}/style-light.css ${agsStyles}/style-dark.css "$files/.config/ags/"

      install_theme() {
        local name=$1
        local mode=$2
        local gtk3_base=$3
        local gtk4_base=$4
        local theme_dir="$files/.local/share/themes/$name"

        mkdir -p "$theme_dir/gtk-3.0" "$theme_dir/gtk-4.0"

        {
          printf '[X-GNOME-Metatheme]\n'
          printf 'Name=%s\n' "$name"
          printf 'Type=X-GNOME-Metatheme\n'
          printf 'Comment=Wallpaper-derived Themegen GTK theme\n'
          printf 'Encoding=UTF-8\n'
          printf 'GtkTheme=%s\n' "$name"
          printf 'IconTheme=Papirus\n'
          printf 'CursorTheme=${cursorTheme.name}\n'
          printf 'CursorSize=${toString cursorTheme.size}\n'
        } > "$theme_dir/index.theme"

        {
          printf '@import url("%s");\n\n' "$gtk3_base"
          cat "$files/.config/gtk-3.0/themegen-$mode.css"
        } > "$theme_dir/gtk-3.0/gtk.css"

        {
          printf '@import url("%s");\n\n' "$gtk4_base"
          cat "$files/.config/gtk-4.0/themegen-$mode.css"
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

      ln -s ${lib.escapeShellArg "${entry.wallpaper}"} "$out/wallpaper"
    '';

  wallpaperSet = pkgs.linkFarm "framework-wallpaper-set" (
    map (entry: {
      name = entry.id;
      path = mkBundle entry;
    }) themegenWallpapers
  );

  themegenTargetsFile = pkgs.writeText "themegen-targets" (lib.concatLines themegenTargets);

  frameworkWallpaper = pkgs.writeShellApplication {
    name = "framework-wallpaper";
    runtimeInputs = [
      pkgs.awww
      pkgs.coreutils
      pkgs.procps
      pkgs.systemd
      pkgs.util-linux
      config.services.darkman.package
    ];
    text = ''
      state_dir=${lib.escapeShellArg themegenStateDir}
      wallpaper_set=${wallpaperSet}
      targets_file=${themegenTargetsFile}
      current="$state_dir/current"
      ids=(${lib.escapeShellArgs wallpaperIds})
      changed=0

      usage() {
        echo "usage: framework-wallpaper <next|restore|prepare|show|current|darkman <light|dark>>" >&2
        exit 2
      }

      import_session_env() {
        if [ -z "''${XDG_RUNTIME_DIR:-}" ]; then
          XDG_RUNTIME_DIR="/run/user/$(id -u)"
          export XDG_RUNTIME_DIR
        fi

        if [ -z "''${WAYLAND_DISPLAY:-}" ] && systemctl --user show-environment >/dev/null 2>&1; then
          while IFS='=' read -r name value; do
            if [ "$name" = WAYLAND_DISPLAY ]; then
              export WAYLAND_DISPLAY="$value"
            fi
          done < <(systemctl --user show-environment)
        fi
      }

      current_id() {
        cat "$current/.themegen/id" 2>/dev/null || true
      }

      has_id() {
        local id
        for id in "''${ids[@]}"; do
          if [ "$id" = "$1" ]; then
            return 0
          fi
        done
        return 1
      }

      pick_random() {
        local exclude=$1 id
        local -a pool=()
        for id in "''${ids[@]}"; do
          if [ "$id" != "$exclude" ]; then
            pool+=("$id")
          fi
        done
        if [ "''${#pool[@]}" -eq 0 ]; then
          pool=("''${ids[@]}")
        fi
        printf '%s\n' "''${pool[@]}" | shuf -n 1
      }

      # Copy instead of linking: kitty only re-reads theme files whose mtime
      # increased, and store files all share the same epoch mtime.
      materialize() {
        local id=$1 bundle tmp old
        bundle=$(readlink -f "$wallpaper_set/$id")
        tmp=$(mktemp -d "$state_dir/render.XXXXXX")
        cp -r --no-preserve=mode,ownership "$bundle/files/." "$tmp/"
        mkdir -p "$tmp/.themegen"
        printf '%s\n' "$id" > "$tmp/.themegen/id"
        printf '%s\n' "$bundle" > "$tmp/.themegen/bundle"
        ln -s "$bundle/wallpaper" "$tmp/.themegen/wallpaper"
        chmod 755 "$tmp"

        ln -sfn "$(basename "$tmp")" "$state_dir/current.new"
        mv -T "$state_dir/current.new" "$current"

        for old in "$state_dir"/render.*; do
          if [ "$old" != "$tmp" ]; then
            rm -rf "$old"
          fi
        done
        changed=1
      }

      # Keep the current wallpaper, refreshing its copy after a rebuild.
      ensure_current() {
        local id
        id=$(current_id)
        if [ -n "$id" ] && has_id "$id"; then
          if [ "$(cat "$current/.themegen/bundle" 2>/dev/null || true)" != "$(readlink -f "$wallpaper_set/$id")" ]; then
            materialize "$id"
          fi
        else
          materialize "$(pick_random "")"
        fi
      }

      rotate() {
        materialize "$(pick_random "$(current_id)")"
      }

      darkman_mode() {
        local mode
        mode=$(darkman get 2>/dev/null || true)
        case "$mode" in
          light | dark) printf '%s\n' "$mode" ;;
        esac
      }

      # Directory watchers (Zed, Pi, Equibop) only see entries change, so
      # atomically replace each Home Manager link with an identical one.
      nudge_links() {
        local target path tmp
        while IFS= read -r target; do
          path="$HOME/$target"
          if [ ! -L "$path" ]; then
            continue
          fi
          tmp="$(dirname "$path")/.$(basename "$path").themegen-nudge"
          ln -sfn "$(readlink "$path")" "$tmp"
          mv -fT "$tmp" "$path"
        done < "$targets_file"
      }

      show_wallpaper() {
        local tries=$1 image
        if [ ! -e "$current/.themegen/wallpaper" ] || [ -z "''${WAYLAND_DISPLAY:-}" ]; then
          return 0
        fi
        image=$(readlink -f "$current/.themegen/wallpaper")
        for _ in $(seq "$tries"); do
          if awww query >/dev/null 2>&1; then
            awww img --transition-type fade --transition-duration 2 "$image"
            return 0
          fi
          sleep 0.2
        done
        echo "framework-wallpaper: awww-daemon is not reachable" >&2
      }

      apply() {
        local mode=$1
        local -a appearance_args=("$mode")
        if [ "$changed" = 1 ]; then
          appearance_args+=(--refresh-gtk)
        fi

        ${frameworkSetAppearance} "''${appearance_args[@]}"

        if [ "$changed" = 1 ]; then
          nudge_links
          pkill -USR1 -x -u "$(id -u)" kitty || true
        fi

        # Already-open fish shells re-emit their terminal palette on change.
        ${config.programs.fish.package}/bin/fish -c 'set -U themegen_generation (date +%s%N)' || true

        show_wallpaper 1
      }

      import_session_env
      mkdir -p "$state_dir"

      case "''${1:-}" in
        current)
          current_id
          exit 0
          ;;
        show)
          show_wallpaper 50
          exit 0
          ;;
      esac

      exec 9>"$state_dir/.lock"
      flock 9

      # A render staged by `prepare` still needs its app reloads.
      if [ -e "$state_dir/pending" ] && [ "''${1:-}" != prepare ]; then
        changed=1
        rm -f "$state_dir/pending"
      fi

      case "''${1:-}" in
        prepare)
          ensure_current
          if [ "$changed" = 1 ]; then
            touch "$state_dir/pending"
          fi
          ;;
        next)
          rotate
          mode=$(darkman_mode)
          apply "''${mode:-dark}"
          ;;
        restore)
          ensure_current
          mode=$(darkman_mode)
          if [ -n "$mode" ]; then
            printf '%s\n' "$mode" > "$state_dir/mode"
          fi
          apply "''${mode:-dark}"
          ;;
        darkman)
          mode=''${2:-}
          case "$mode" in
            light | dark) ;;
            *) usage ;;
          esac
          last_mode=$(cat "$state_dir/mode" 2>/dev/null || true)
          # Rotate only on a real sunrise/sunset transition, not on login.
          if [ -n "$last_mode" ] && [ "$last_mode" != "$mode" ]; then
            rotate
          else
            ensure_current
          fi
          printf '%s\n' "$mode" > "$state_dir/mode"
          apply "$mode"
          ;;
        *)
          usage
          ;;
      esac
    '';
  };

  outOfStoreCurrent =
    target: config.lib.file.mkOutOfStoreSymlink "${themegenStateDir}/current/${target}";
in
{
  themegen.wallpapers = desktopWallpapers;

  home.packages = [
    pkgs.awww
    frameworkWallpaper
  ];

  xdg.configFile = {
    "ags/style-light.css".source = outOfStoreCurrent ".config/ags/style-light.css";
    "ags/style-dark.css".source = outOfStoreCurrent ".config/ags/style-dark.css";
  };

  xdg.dataFile = {
    "themes/Themegen".source = outOfStoreCurrent ".local/share/themes/Themegen";
    "themes/Themegen-dark".source = outOfStoreCurrent ".local/share/themes/Themegen-dark";
  };

  # libadwaita ignores gtk-theme and only reads user CSS at startup.
  gtk.gtk4.extraCss = ''
    @import url("file://${config.xdg.dataHome}/themes/Themegen-dark/gtk-4.0/gtk.css");
  '';

  systemd.user.services.awww-daemon = {
    Unit = {
      Description = "awww wallpaper daemon";
      ConditionEnvironment = [ "WAYLAND_DISPLAY" ];
      PartOf = [ "graphical-session.target" ];
      After = [
        "niri.service"
        "graphical-session.target"
      ];
      Wants = [ "graphical-session.target" ];
    };

    Service = {
      Type = "simple";
      ExecStart = "${pkgs.awww}/bin/awww-daemon";
      ExecStartPost = "${frameworkWallpaper}/bin/framework-wallpaper show";
      Restart = "on-failure";
      RestartSec = 2;
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  services.darkman = {
    darkModeScripts.themegen = "${frameworkWallpaper}/bin/framework-wallpaper darkman dark";
    lightModeScripts.themegen = "${frameworkWallpaper}/bin/framework-wallpaper darkman light";
  };

  # Populate the state directory before links to it appear (niri would
  # otherwise briefly see a dangling theme include), then reload apps.
  home.activation = {
    frameworkWallpaperPrepare = lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ] ''
      run ${frameworkWallpaper}/bin/framework-wallpaper prepare \
        || echo "framework-wallpaper: prepare failed" >&2
    '';
    frameworkWallpaper = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      run ${frameworkWallpaper}/bin/framework-wallpaper restore \
        || echo "framework-wallpaper: restore failed" >&2
    '';
  };
}
