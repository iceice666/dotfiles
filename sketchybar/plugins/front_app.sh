#!/usr/bin/env sh

APP_NAME="${INFO:-}"

if [ -z "$APP_NAME" ]; then
  sketchybar --set "$NAME" drawing=off
  exit 0
fi

sketchybar --set "$NAME" drawing=on label="$APP_NAME" background.image="app.$APP_NAME"
