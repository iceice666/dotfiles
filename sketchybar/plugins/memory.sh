#!/usr/bin/env sh

memory_pressure="$(memory_pressure 2>/dev/null | awk -F': ' '/System-wide memory free percentage/ {print $2}' | tr -d '%')"

if [ -n "$memory_pressure" ]; then
  used=$((100 - memory_pressure))
  label="${used}%"
else
  label="--"
fi

sketchybar --set "$NAME" label="$label"
