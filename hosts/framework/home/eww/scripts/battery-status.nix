{
  mkScript,
  themeColorFunction,
  icons,
  pkgs,
  ...
}:
{
  batteryStatus =
    mkScript "eww-battery-status"
      (with pkgs; [
        gawk
        jq
      ])
      ''
        ${themeColorFunction}

        foreground="$(theme_color foreground '#e5e5e5')"
        critical="$(theme_color critical '#ef4444')"
        warning="$(theme_color warning '#f59e0b')"
        success="$(theme_color success '#22c55e')"

        battery=""
        for candidate in /sys/class/power_supply/BAT*; do
          if [ -d "$candidate" ]; then
            battery="$candidate"
            break
          fi
        done

        if [ -z "$battery" ]; then
          jq -cn \
            --arg text "--" \
            --arg class "island battery" \
            --arg icon "${icons.batteryUnknown}" \
            --arg color "$foreground" \
            '{ text: $text, class: $class, icon: $icon, color: $color }'
          exit 0
        fi

        capacity="--"
        status="Unknown"
        [ -r "$battery/capacity" ] && capacity="$(cat "$battery/capacity")"
        [ -r "$battery/status" ] && status="$(cat "$battery/status")"

        class="island battery"
        icon="${icons.batteryNormal}"
        color="$foreground"
        case "$status" in
          Charging)
            class="$class charging"
            icon="${icons.batteryCharging}"
            color="$success"
            ;;
          Discharging|Not\ charging|Unknown)
            if [ "$capacity" != "--" ] && [ "$capacity" -le 15 ]; then
              class="$class critical"
              color="$critical"
            elif [ "$capacity" != "--" ] && [ "$capacity" -le 30 ]; then
              class="$class warning"
              color="$warning"
            fi
            ;;
          Full)
            class="$class charging"
            color="$success"
            ;;
        esac

        jq -cn \
          --arg text "$capacity%" \
          --arg class "$class" \
          --arg icon "$icon" \
          --arg color "$color" \
          '{ text: $text, class: $class, icon: $icon, color: $color }'
      '';
}
