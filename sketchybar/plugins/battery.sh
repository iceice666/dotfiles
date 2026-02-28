#!/usr/bin/env sh

CONFIG_DIR="$HOME/.config/sketchybar"
. "$CONFIG_DIR/colors.sh"

batt_info="$(pmset -g batt | sed -nE 's/.*([0-9]+%).*/\1/p' | sed -n '1p')"
pct="${batt_info%\%}"
charging=0

if pmset -g batt | grep -q "AC Power"; then
  charging=1
fi

if [ -z "$pct" ]; then
  sketchybar --set "$NAME" label="--"
  exit 0
fi

# Nerd Font (Font Awesome) battery codepoints - U+F244 empty, U+F243 1/4, U+F242 1/2, U+F241 3/4, U+F240 full, U+F0E7 bolt
if [ "$charging" -eq 1 ]; then
  icon=$(printf '\357\203\247')   # U+F0E7 bolt/charging
elif [ "$pct" -ge 90 ]; then
  icon=$(printf '\357\210\200')    # U+F240 full
elif [ "$pct" -ge 70 ]; then
  icon=$(printf '\357\210\201')    # U+F241 3/4
elif [ "$pct" -ge 45 ]; then
  icon=$(printf '\357\210\202')    # U+F242 1/2
elif [ "$pct" -ge 20 ]; then
  icon=$(printf '\357\210\203')    # U+F243 1/4
else
  icon=$(printf '\357\210\204')    # U+F244 empty
fi

color="$GREEN"
if [ "$pct" -lt 20 ]; then
  color="$RED"
elif [ "$pct" -le 50 ]; then
  color="$YELLOW"
fi

sketchybar --set "$NAME" icon="$icon" icon.color="$color" label="${pct}%"
