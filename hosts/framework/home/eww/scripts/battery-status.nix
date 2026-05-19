{
  mkScript,
  themeColorFunction,
  icons,
  pkgs,
  ...
}:
let
  batteryStatusFunction = ''
    ${themeColorFunction}

    is_integer() {
      case "$1" in
        ""|*[!0-9]*)
          return 1
          ;;
        *)
          return 0
          ;;
      esac
    }

    upower_field() {
      device="$1"
      field="$2"
      upower --show-info "$device" 2>/dev/null | awk -F: -v field="$field" '
        $1 ~ "^[[:space:]]*" field "$" {
          value = $2
          sub(/^[[:space:]]*/, "", value)
          print value
          exit
        }
      '
    }

    display_device() {
      upower --enumerate 2>/dev/null | awk '/DisplayDevice$/ { print; exit }'
    }

    battery_device() {
      upower --enumerate 2>/dev/null | awk '/\/battery_/ { print; exit }'
    }

    daemon_on_battery() {
      upower --dump 2>/dev/null | awk -F: '
        $1 ~ /^[[:space:]]*on-battery$/ {
          value = $2
          sub(/^[[:space:]]*/, "", value)
          print value
          exit
        }
      '
    }

    emit_battery_status() {
      foreground="$(theme_color foreground '#e5e5e5')"
      critical="$(theme_color critical '#ef4444')"
      warning="$(theme_color warning '#f59e0b')"
      success="$(theme_color success '#22c55e')"

      device="$(display_device)"
      if [ -z "$device" ]; then
        device="$(battery_device)"
      fi

      percentage="$(upower_field "$device" percentage)"
      capacity="''${percentage%\%}"
      capacity="''${capacity%.*}"
      state="$(upower_field "$device" state)"
      on_battery="$(daemon_on_battery)"

      if [ -z "$device" ] || [ -z "$percentage" ]; then
        jq -cn \
          --arg text "--" \
          --arg class "island battery" \
          --arg icon "${icons.batteryUnknown}" \
          --arg color "$foreground" \
          '{ text: $text, class: $class, icon: $icon, color: $color }'
        return 0
      fi

      class="island battery"
      icon="${icons.batteryNormal}"
      color="$foreground"

      if [ "$state" = "charging" ] || [ "$state" = "fully-charged" ] || [ "$on_battery" = "no" ]; then
        class="$class charging"
        icon="${icons.batteryCharging}"
        color="$success"
      elif is_integer "$capacity" && [ "$capacity" -le 15 ]; then
        class="$class critical"
        color="$critical"
      elif is_integer "$capacity" && [ "$capacity" -le 30 ]; then
        class="$class warning"
        color="$warning"
      fi

      jq -cn \
        --arg text "$percentage" \
        --arg class "$class" \
        --arg icon "$icon" \
        --arg color "$color" \
        '{ text: $text, class: $class, icon: $icon, color: $color }'
    }
  '';
in
{
  batteryStatus =
    mkScript "eww-battery-status"
      (with pkgs; [
        coreutils
        gawk
        jq
        upower
      ])
      ''
        ${batteryStatusFunction}
        emit_battery_status
      '';

  batteryStatusListen =
    mkScript "eww-battery-status-listen"
      (with pkgs; [
        coreutils
        gawk
        jq
        upower
      ])
      ''
        ${batteryStatusFunction}

        progressive_poll() {
          emit_battery_status
          for delay in 1 1 3 5 20 30; do
            sleep "$delay"
            emit_battery_status
          done
        }

        emit_battery_status

        while :; do
          timeout 60s upower --monitor 2>/dev/null \
            | while IFS= read -r event; do
              case "$event" in
                *"device changed:"*|*"device added:"*|*"device removed:"*|*"daemon changed:"*)
                  progressive_poll
                  ;;
              esac
            done || true
          emit_battery_status
        done
      '';
}
