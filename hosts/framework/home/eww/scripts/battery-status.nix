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
      { upower --show-info "$device" 2>/dev/null || true; } | awk -F: -v field="$field" '
        $1 ~ "^[[:space:]]*" field "$" {
          value = $2
          sub(/^[[:space:]]*/, "", value)
          print value
          exit
        }
      '
    }

    display_device() {
      { upower --enumerate 2>/dev/null || true; } | awk '/DisplayDevice$/ { print; exit }'
    }

    battery_device() {
      { upower --enumerate 2>/dev/null || true; } | awk '/\/battery_/ { print; exit }'
    }

    daemon_on_battery() {
      { upower --dump 2>/dev/null || true; } | awk -F: '
        $1 ~ /^[[:space:]]*on-battery$/ {
          value = $2
          sub(/^[[:space:]]*/, "", value)
          print value
          exit
        }
      '
    }

    tlp_mode() {
      { tlp-stat -s 2>/dev/null || true; } | awk -F= '
        $1 ~ /^[[:space:]]*Mode[[:space:]]*$/ {
          value = $2
          sub(/^[[:space:]]*/, "", value)
          sub(/[[:space:]]*$/, "", value)
          print value
          exit
        }
      '
    }

    emit_battery_status() {
      foreground="$(theme_color foreground '#e5e5e5')"

      device="$(display_device)"
      if [ -z "$device" ]; then
        device="$(battery_device)"
      fi

      percentage="$(upower_field "$device" percentage)"
      capacity="''${percentage%\%}"
      capacity="''${capacity%.*}"
      state="$(upower_field "$device" state)"
      on_battery="$(daemon_on_battery)"
      mode="$(tlp_mode)"

      if [ -z "$device" ] || [ -z "$percentage" ]; then
        jq -cn \
          --argjson value 0 \
          --arg text "--" \
          --arg tooltip "Battery --" \
          --arg class "island battery unknown" \
          --arg icon "${icons.batteryUnknown}" \
          --arg color "$foreground" \
          '{
            value: $value,
            text: $text,
            tooltip: $tooltip,
            class: $class,
            icon: $icon,
            color: $color
          }'
        return 0
      fi

      class="island battery"
      icon="${icons.batteryUnknown}"
      color="$foreground"
      profile="Unknown"

      case "$mode" in
        AC)
          icon="${icons.batteryAc}"
          profile="AC"
          ;;
        BAT)
          icon="${icons.batteryBat}"
          profile="Battery"
          ;;
      esac

      if [ "$mode" = "unknown" ] || [ -z "$mode" ]; then
        if [ "$state" = "charging" ] || [ "$state" = "fully-charged" ] || [ "$on_battery" = "no" ]; then
          icon="${icons.batteryAc}"
          profile="AC"
        elif [ "$on_battery" = "yes" ]; then
          icon="${icons.batteryBat}"
          profile="Battery"
        fi
      fi

      if is_integer "$capacity"; then
        value="$capacity"
        if [ "$value" -lt 0 ]; then
          value=0
        elif [ "$value" -gt 100 ]; then
          value=100
        fi
      else
        value=0
      fi

      if [ "$state" = "charging" ] || [ "$state" = "fully-charged" ] || [ "$mode" = "AC" ] || [ "$on_battery" = "no" ]; then
        class="$class charging"
      elif [ "$value" -lt 10 ]; then
        class="$class critical"
      elif [ "$value" -lt 30 ]; then
        class="$class low"
      elif [ "$value" -lt 50 ]; then
        class="$class medium"
      elif [ "$value" -lt 80 ]; then
        class="$class good"
      else
        class="$class full"
      fi

      tooltip="$percentage - $profile profile"

      jq -cn \
        --argjson value "$value" \
        --arg text "$percentage" \
        --arg tooltip "$tooltip" \
        --arg class "$class" \
        --arg icon "$icon" \
        --arg color "$color" \
        '{
          value: $value,
          text: $text,
          tooltip: $tooltip,
          class: $class,
          icon: $icon,
          color: $color
        }'
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
        tlp
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
        tlp
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
