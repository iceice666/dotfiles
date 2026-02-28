#!/usr/bin/env sh

if [ -z "$INFO" ] || [ "$INFO" = "{}" ]; then
  sketchybar --set "$NAME" drawing=off
  exit 0
fi

artist="$(echo "$INFO" | jq -r '.artist // empty')"
title="$(echo "$INFO" | jq -r '.title // empty')"

if [ -z "$artist" ] && [ -z "$title" ]; then
  sketchybar --set "$NAME" drawing=off
  exit 0
fi

label="$artist - $title"
label="$(echo "$label" | sed 's/^ - //; s/ - $//')"

sketchybar --set "$NAME" drawing=on label="$label"
