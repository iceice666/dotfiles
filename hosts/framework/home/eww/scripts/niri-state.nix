{
  mkScript,
  commonInputs,
  icons,
  pkgs,
  ...
}:
{
  niriState =
    mkScript "eww-niri-state"
      (
        commonInputs
        ++ (with pkgs; [
          findutils
          gnused
        ])
      )
      ''
        runtime_dir="''${XDG_RUNTIME_DIR:-/tmp}"
        cache_dir="$runtime_dir/eww-icon-cache"
        mkdir -p "$cache_dir"

        data_dirs() {
          if [ -n "''${HOME:-}" ]; then
            printf '%s\n' "$HOME/.local/share"
          fi
          if [ -n "''${XDG_DATA_DIRS:-}" ]; then
            printf '%s' "$XDG_DATA_DIRS" | tr ':' '\n'
          fi
          printf '%s\n' \
            /run/current-system/sw/share \
            /etc/profiles/per-user/iceice666/share \
            /usr/local/share \
            /usr/share
        }

        icon_themes() {
          active_theme="$(readlink "$HOME/.config/eww/theme.scss" 2>/dev/null || true)"
          case "$active_theme" in
            *light*) printf '%s\n' Papirus Papirus-Dark hicolor Adwaita ;;
            *) printf '%s\n' Papirus-Dark Papirus hicolor Adwaita ;;
          esac
        }

        cache_key() {
          printf '%s' "$1" | sha256sum | awk '{ print $1 }'
        }

        read_desktop_key() {
          key="$1"
          file="$2"
          awk -F= -v wanted="$key" '
            /^\[/ { in_entry = ($0 == "[Desktop Entry]"); next }
            in_entry && $1 == wanted {
              sub(/^[^=]*=/, "")
              print
              exit
            }
          ' "$file"
        }

        find_icon_name() {
          icon="$1"
          shift

          if [ -z "$icon" ]; then
            return 1
          fi

          if [ "''${icon#/}" != "$icon" ]; then
            if [ -e "$icon" ]; then
              printf '%s\n' "$icon"
              return 0
            fi
            return 1
          fi

          for base in "$@"; do
            [ -d "$base" ] || continue

            while IFS= read -r theme; do
              theme_dir="$base/$theme"
              [ -d "$theme_dir" ] || continue

              candidate="$(
                find -L "$theme_dir" -type f \
                  \( -name "$icon.png" -o -name "$icon.svg" -o -name "$icon.xpm" -o -name "$icon" \) \
                  2>/dev/null \
                  | awk '
                    /\/24x24\// { print "0 " $0; next }
                    /\/32x32\// { print "1 " $0; next }
                    /\/48x48\// { print "2 " $0; next }
                    /\/scalable\// { print "3 " $0; next }
                    /\.png$/ { print "4 " $0; next }
                    /\.svg$/ { print "5 " $0; next }
                    { print "6 " $0 }
                  ' \
                  | sort -n \
                  | sed 's/^[0-9] //' \
                  | head -n 1
              )"
              if [ -n "$candidate" ]; then
                printf '%s\n' "$candidate"
                return 0
              fi
            done < <(icon_themes)

            candidate="$(
              find -L "$base" -maxdepth 2 -type f \
                \( -name "$icon.png" -o -name "$icon.svg" -o -name "$icon.xpm" -o -name "$icon" \) \
                2>/dev/null \
                | sort \
                | head -n 1
            )"
            if [ -n "$candidate" ]; then
              printf '%s\n' "$candidate"
              return 0
            fi
          done

          return 1
        }

        resolve_icon() {
          app_id="''${1:-}"
          title="''${2:-}"
          placeholder_icon="${icons.appPlaceholder}"
          if [ -n "$app_id" ]; then
            key="$(cache_key "app:$app_id")"
          else
            key="$(cache_key "title:$title")"
          fi
          cache_file="$cache_dir/$key"
          if [ -r "$cache_file" ]; then
            cached_path="$(cat "$cache_file")"
            if [ -n "$cached_path" ] && [ "$cached_path" != "$placeholder_icon" ] && [ -e "$cached_path" ]; then
              printf '%s\n' "$cached_path"
              return
            fi
          fi

          app_lc="$(printf '%s' "$app_id" | tr '[:upper:]' '[:lower:]')"
          title_lc="$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]')"
          icon=""
          desktop_dir=""

          while IFS= read -r data_dir; do
            apps_dir="$data_dir/applications"
            [ -d "$apps_dir" ] || continue

            while IFS= read -r desktop; do
              stem="$(basename "$desktop" .desktop | tr '[:upper:]' '[:lower:]')"
              startup="$(read_desktop_key StartupWMClass "$desktop" | tr '[:upper:]' '[:lower:]')"
              exec_value="$(read_desktop_key Exec "$desktop" | tr '[:upper:]' '[:lower:]')"

              match=false
              if [ -n "$app_lc" ]; then
                if [ "$stem" = "$app_lc" ] \
                  || [ "$startup" = "$app_lc" ] \
                  || [[ "$exec_value" == *"$app_lc"* ]] \
                  || [[ "$app_lc" == *"$stem"* ]]; then
                  match=true
                fi
              fi
              if [ "$match" = false ] && [ -n "$title_lc" ]; then
                if [[ "$title_lc" == *"$stem"* ]] || { [ -n "$startup" ] && [[ "$title_lc" == *"$startup"* ]]; }; then
                  match=true
                fi
              fi

              if [ "$match" = true ]; then
                icon="$(read_desktop_key Icon "$desktop")"
                desktop_dir="$(dirname "$(dirname "$desktop")")"
                break 2
              fi
            done < <(find -L "$apps_dir" -type f -name '*.desktop' 2>/dev/null | sort)
          done < <(data_dirs | awk '!seen[$0]++')

          icon_dirs=()
          if [ -n "$desktop_dir" ]; then
            icon_dirs+=("$desktop_dir/icons" "$desktop_dir/pixmaps")
          fi
          while IFS= read -r data_dir; do
            icon_dirs+=("$data_dir/icons" "$data_dir/pixmaps")
          done < <(data_dirs | awk '!seen[$0]++')

          path="$(find_icon_name "$icon" "''${icon_dirs[@]}" || true)"
          if [ -z "$path" ]; then
            printf '%s\n' "$placeholder_icon"
            return
          fi

          printf '%s\n' "$path" > "$cache_file"
          printf '%s\n' "$path"
        }

        snapshot() {
          windows="$(niri msg -j windows 2>/dev/null || printf '[]')"
          workspaces="$(niri msg -j workspaces 2>/dev/null || printf '[]')"
          outputs="$(niri msg -j outputs 2>/dev/null || printf '{}')"

          icon_rows="$(
            jq -r '
              .[]?
              | select(.id != null)
              | [
                  (.id | tostring),
                  (.app_id // ""),
                  (.title // .app_id // "Desktop")
                ]
              | @tsv
            ' <<< "$windows" 2>/dev/null || true
          )"

          icon_json="$(
            while IFS=$'\t' read -r id app title; do
              [ -n "$id" ] || continue
              icon_path="$(resolve_icon "$app" "$title")"
              jq -cn --arg id "$id" --arg path "$icon_path" '{ key: $id, value: $path }'
            done <<< "$icon_rows" | jq -cs 'from_entries'
          )"

          jq -cn \
            --argjson windows "$windows" \
            --argjson workspaces "$workspaces" \
            --argjson outputs "$outputs" \
            --argjson icons "$icon_json" '
              def workspaceLabel:
                (.name // (.idx // .index // .id | tostring) // "?");

              def workspaceOutput:
                .output // .output_name // .monitor // "";

              def visibleWorkspace:
                (.is_active // .active // .is_focused // .focused // false);

              def windowWorkspaceId:
                .workspace_id // .workspace // null;

              def windowOrder:
                (
                  .layout.pos_in_scrolling_layout
                  // .layout.tile_pos_in_workspace_view
                  // [999999999, 999999999]
                ) as $position
                | [
                    ($position[0] // 999999999),
                    ($position[1] // 999999999),
                    (.id // 999999999)
                  ];

              def outputNames:
                if ($outputs | type) == "array" then
                  [ $outputs[]? | .name // .output // empty ]
                elif ($outputs | type) == "object" then
                  [ $outputs | keys[] ]
                else
                  []
                end;

              def focusedTitle($monitor):
                first(
                  $windows[]?
                  | select(.is_focused // .focused // false)
                  | (.title // .app_id // "Desktop")
                ) // "Desktop";

              def monitorWorkspaces($monitor):
                [
                  $workspaces[]?
                  | select(workspaceOutput == $monitor)
                  | select(visibleWorkspace)
                  | . as $workspace
                  | {
                    label: ($workspace | workspaceLabel),
                    windows: [
                      $windows[]?
                      | select(windowWorkspaceId == ($workspace.id // null))
                    ]
                    | sort_by(windowOrder)
                    | map({
                        id,
                        title: (.title // .app_id // "Desktop"),
                        focused: (.is_focused // .focused // false),
                        icon_path: ($icons[(.id | tostring)] // "${icons.appPlaceholder}")
                      })
                  }
                ];

              (outputNames) as $outputNames |
              (if ($outputNames | length) > 0 then
                $outputNames
              else
                [ $workspaces[]? | workspaceOutput ] | unique | map(select(. != ""))
              end) as $monitors |
              {
                groups: [
                  $monitors[] as $monitor |
                  {
                    monitor: $monitor,
                    workspaces: monitorWorkspaces($monitor)
                  }
                ],
                outputs: (
                  reduce $monitors[] as $monitor ({};
                    .[$monitor] = {
                      focused_title: focusedTitle($monitor),
                      workspaces: monitorWorkspaces($monitor)
                    }
                  )
                )
              }
            '
        }

        snapshot
        niri msg event-stream 2>/dev/null | while IFS= read -r _; do
          snapshot
        done
      '';
}
