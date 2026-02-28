# Left-side bar items: mode indicator + workspace buttons
{ colors, aerospace }:

''
  # ── Left: Aerospace mode indicator ──────────────────────────────────────────
  sketchybar \
    --add item aerospace_mode left \
    --set aerospace_mode \
      drawing=off \
      icon.drawing=off \
      label.font="SF Pro:Bold:12.0" \
      label.padding_left=8 \
      label.padding_right=8 \
      background.color=${colors.bg2} \
      background.height=24 \
      script="${aerospace.mode}" \
    --subscribe aerospace_mode aerospace_mode_change

  # ── Left: Aerospace workspaces ───────────────────────────────────────────────
  for sid in $(aerospace list-workspaces --all 2>/dev/null); do
    sketchybar \
      --add item "space.$sid" left \
      --set "space.$sid" \
        label="$sid" \
        label.font="sketchybar-app-font:Regular:14.0" \
        label.padding_left=8 \
        label.padding_right=8 \
        icon.drawing=off \
        background.height=24 \
        background.corner_radius=6 \
        background.drawing=off \
        click_script="aerospace workspace $sid" \
        script="${aerospace.workspace} $sid" \
      --subscribe "space.$sid" \
        aerospace_workspace_change \
        aerospace_focus_change \
        front_app_switched \
        space_change
  done
''
