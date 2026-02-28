#!/usr/bin/env sh

CONFIG_DIR="$HOME/.config/sketchybar"
. "$CONFIG_DIR/colors.sh"

SID="${NAME#space.}"
FOCUSED="${FOCUSED_WORKSPACE:-}"

# Hide workspace if it has no windows
if command -v aerospace >/dev/null 2>&1; then
  if aerospace list-windows --workspace "$SID" 2>/dev/null | grep -q .; then
    drawing=on
  else
    drawing=off
  fi
else
  drawing=on
fi
sketchybar --set "$NAME" drawing="$drawing"

if [ -z "$FOCUSED" ] && command -v aerospace >/dev/null 2>&1; then
  FOCUSED="$(aerospace list-workspaces --focused 2>/dev/null)"
fi

if [ "$SID" = "$FOCUSED" ]; then
  sketchybar --set "$NAME" background.color="$BLUE" label.color=0xFF000000 icon.color=0xFF000000
else
  sketchybar --set "$NAME" background.color="$ITEM_BG" label.color="$TEXT" icon.color="$TEXT"
fi
