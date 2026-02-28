#!/usr/bin/env sh

cpu_line="$(top -l 1 -n 0 | awk -F'[:,]' '/CPU usage/ {print $2}')"
cpu_pct="$(echo "$cpu_line" | awk '{printf "%.0f%%", $1}')"

[ -z "$cpu_pct" ] && cpu_pct="0%"

sketchybar --set "$NAME" label="$cpu_pct"
