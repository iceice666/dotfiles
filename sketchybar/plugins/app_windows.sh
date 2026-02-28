#!/usr/bin/env sh

icon_map() {
  case "$1" in
    "Arc") echo "󰇧" ;;
    "Safari") echo "󰀹" ;;
    "Google Chrome") echo "󰊯" ;;
    "WezTerm"|"Terminal"|"iTerm2") echo "󰆍" ;;
    "Finder") echo "󰀶" ;;
    "Discord") echo "󰙯" ;;
    "Spotify") echo "󰓇" ;;
    "Messages") echo "󰍩" ;;
    "Mail") echo "󰇮" ;;
    "Notion") echo "󰈙" ;;
    "Zed") echo "󰘦" ;;
    "Code") echo "󰨞" ;;
    *) echo "󰣆" ;;
  esac
}

apps=""
if command -v aerospace >/dev/null 2>&1; then
  apps="$(aerospace list-windows --workspace focused --format '%{app-name}' 2>/dev/null | awk '!seen[$0]++')"
fi

icons=""
if [ -n "$apps" ]; then
  while IFS= read -r app; do
    [ -z "$app" ] && continue
    icons="$icons $(icon_map "$app")"
  done <<EOF
$apps
EOF
fi

[ -z "$icons" ] && icons="—"

focused_label=""
if [ "$SENDER" = "front_app_switched" ] && [ -n "$INFO" ]; then
  focused_label="  $INFO"
fi

sketchybar --set "$NAME" label="$icons$focused_label"
