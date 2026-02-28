# Battery status plugin
{ pkgs, colors }:

pkgs.writeShellScript "sketchybar-battery" ''
  #!/usr/bin/env bash
  BATT_INFO=$(pmset -g batt)
  PCT=$(echo "$BATT_INFO" | grep -o '[0-9]*%' | head -1 | tr -d '%')
  CHARGING=$(echo "$BATT_INFO" | grep -c 'AC Power')

  if [ "$CHARGING" -gt 0 ]; then
    if   [ "$PCT" -ge 90 ]; then ICON="󰂅"
    elif [ "$PCT" -ge 70 ]; then ICON="󰂋"
    elif [ "$PCT" -ge 50 ]; then ICON="󰂉"
    elif [ "$PCT" -ge 30 ]; then ICON="󰂇"
    else                         ICON="󰢜"
    fi
    COLOR="${colors.green}"
  else
    if   [ "$PCT" -ge 80 ]; then ICON="󰁹"; COLOR="${colors.fg}"
    elif [ "$PCT" -ge 60 ]; then ICON="󰁿"; COLOR="${colors.fg}"
    elif [ "$PCT" -ge 40 ]; then ICON="󰁼"; COLOR="${colors.fg}"
    elif [ "$PCT" -ge 20 ]; then ICON="󰁺"; COLOR="${colors.yellow}"
    else                         ICON="󰂎"; COLOR="${colors.red}"
    fi
  fi
  sketchybar --set battery \
    icon="$ICON" \
    icon.color="$COLOR" \
    label="$PCT%"
''
