# Aerospace workspace + mode indicator plugins
{ pkgs, colors, appFont }:

{
  workspace = pkgs.writeShellScript "sketchybar-aerospace-workspace" ''
    #!/usr/bin/env bash
    # Arguments: $1 = workspace id this item represents
    WS_ID="$1"

    source "${appFont}/bin/icon_map.sh"

    # Determine if this workspace is focused
    FOCUSED=$(aerospace list-workspaces --focused 2>/dev/null)

    # Get windows on this workspace
    WIN_COUNT=$(aerospace list-windows --workspace "$WS_ID" 2>/dev/null | wc -l | tr -d ' ')

    if [ "$WIN_COUNT" -eq 0 ] 2>/dev/null; then
      # Empty workspace — hide
      sketchybar --set "$NAME" drawing=off
      return
    fi

    sketchybar --set "$NAME" drawing=on

    if [ "$WS_ID" = "$FOCUSED" ]; then
      # Focused: show workspace number + app icons for all windows
      APPS=$(aerospace list-windows --workspace "$WS_ID" --format '%{app-name}' 2>/dev/null)
      ICONS=""
      while IFS= read -r app; do
        [ -z "$app" ] && continue
        __icon_map "$app"
        ICONS="$ICONS $icon_result"
      done <<< "$APPS"
      LABEL=$(echo "$WS_ID $ICONS" | xargs)

      sketchybar --set "$NAME" \
        label="$LABEL" \
        label.color="${colors.fg}" \
        background.color="${colors.bg2}" \
        background.drawing=on \
        background.border_color="${colors.blue}" \
        background.border_width=1
    else
      # Non-empty but not focused: show number only, dim
      sketchybar --set "$NAME" \
        label="$WS_ID" \
        label.color="${colors.subtext}" \
        background.color="${colors.bg1}" \
        background.drawing=on \
        background.border_color="${colors.border}" \
        background.border_width=0
    fi
  '';

  mode = pkgs.writeShellScript "sketchybar-aerospace-mode" ''
    #!/usr/bin/env bash
    # MODE env var is set by the trigger: --trigger aerospace_mode_change MODE=<mode>
    CURRENT_MODE="''${MODE:-$(aerospace list-modes --current 2>/dev/null)}"

    case "$CURRENT_MODE" in
      main)
        sketchybar --set aerospace_mode drawing=off
        ;;
      resize)
        sketchybar --set aerospace_mode \
          drawing=on \
          label="RESIZE" \
          label.color="${colors.yellow}" \
          background.color="${colors.bg2}" \
          background.border_color="${colors.yellow}" \
          background.border_width=1
        ;;
      *)
        sketchybar --set aerospace_mode \
          drawing=on \
          label="$(echo "$CURRENT_MODE" | tr '[:lower:]' '[:upper:]')" \
          label.color="${colors.mauve}" \
          background.color="${colors.bg2}" \
          background.border_color="${colors.mauve}" \
          background.border_width=1
        ;;
    esac
  '';
}
