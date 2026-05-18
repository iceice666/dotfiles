{
  mkScript,
  notificationStateFunction,
  themeColorFunction,
  pkgs,
  ...
}:
{
  notificationsStatus =
    mkScript "eww-notifications-status"
      (with pkgs; [
        gawk
        gnugrep
        jq
        mako
        util-linux
      ])
      ''
        ${themeColorFunction}
        ${notificationStateFunction}

        foreground="$(theme_color foreground '#e5e5e5')"
        critical="$(theme_color critical '#ef4444')"

        count=0
        notification_state_setup
        history_ids="$(
          makoctl history 2>/dev/null \
            | awk '/^Notification [0-9]+:/ { id = $2; sub(/:$/, "", id); print id }'
        )"

        {
          flock 9
          unread_tmp="$(mktemp)"
          while IFS= read -r unread_id; do
            [ -n "$unread_id" ] || continue
            if printf '%s\n' "$history_ids" | grep -Fxq "$unread_id"; then
              printf '%s\n' "$unread_id"
            fi
          done < "$notification_unread_file" | sort -n -u > "$unread_tmp"

          mv "$unread_tmp" "$notification_unread_file"
          count="$(awk 'END { print NR + 0 }' "$notification_unread_file")"
        } 9>"$notification_lock_file"

        label="$count"
        if [ "''${count:-0}" -gt 99 ]; then
          label="99+"
        fi

        class="island notifications"
        color="$foreground"
        if [ "''${count:-0}" -gt 0 ]; then
          class="$class active"
          color="$critical"
        fi

        jq -cn \
          --argjson count "''${count:-0}" \
          --arg label "$label" \
          --arg class "$class" \
          --arg color "$color" \
          '{ count: $count, label: $label, class: $class, color: $color }'
      '';
}
