#!/usr/bin/env sh

MODE_VALUE="${MODE:-main}"

if [ "$MODE_VALUE" = "resize" ]; then
  sketchybar --set "$NAME" drawing=on background.drawing=on
else
  sketchybar --set "$NAME" drawing=off
fi
