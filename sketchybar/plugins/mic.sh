#!/usr/bin/env sh

CONFIG_DIR="$HOME/.config/sketchybar"
. "$CONFIG_DIR/colors.sh"

mic_active=0
camera_active=0

if ioreg -c AppleHDAEngineInput -r 2>/dev/null | grep -q "IOAudioEngineState.*1"; then
  mic_active=1
fi

if pgrep -q "AppleCameraAssistant|VDCAssistant"; then
  camera_active=1
fi

if [ "$mic_active" -eq 0 ] && [ "$camera_active" -eq 0 ]; then
  sketchybar --set "$NAME" drawing=off
  exit 0
fi

label=""
[ "$mic_active" -eq 1 ] && label="$label MIC"
[ "$camera_active" -eq 1 ] && label="$label CAM"
label="$(echo "$label" | xargs)"

sketchybar --set "$NAME" drawing=on icon.color="$RED" label.color="$RED" label="$label"
