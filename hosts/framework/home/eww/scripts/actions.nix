{
  mkScript,
  commonInputs,
  ewwConfigDir,
  notificationStateFunction,
  pkgs,
  ...
}:
let
  pollEww = mkScript "poll-eww" [ pkgs.eww ] ''
    if eww --config ${ewwConfigDir} ping >/dev/null 2>&1; then
      eww --config ${ewwConfigDir} poll "$@" >/dev/null 2>&1 || true
    fi
  '';

  reloadEww =
    mkScript "reload-eww"
      [
        pkgs.eww
        pkgs.systemd
      ]
      ''
        if eww --config ${ewwConfigDir} ping >/dev/null 2>&1; then
          (cd ${ewwConfigDir} && eww --config ${ewwConfigDir} reload) >/dev/null 2>&1 || true
          systemctl --user try-restart framework-eww-bars.service >/dev/null 2>&1 || true
        elif systemctl --user is-active --quiet framework-eww.service; then
          systemctl --user try-restart framework-eww.service framework-eww-bars.service >/dev/null 2>&1 || true
        fi
      '';

  changeAudioVolume =
    name: device:
    mkScript name
      [
        pkgs.eww
        pkgs.wireplumber
      ]
      ''
        direction="''${1:-}"

        case "$direction" in
          up)
            wpctl set-volume ${device} 0.05+ -l 1.0
            ;;
          down)
            wpctl set-volume ${device} 0.05-
            ;;
          *)
            exit 0
            ;;
        esac

        ${pollEww} audio
      '';
in
{
  changeMicVolume = changeAudioVolume "eww-change-mic-volume" "@DEFAULT_AUDIO_SOURCE@";

  changeSpeakerVolume = changeAudioVolume "eww-change-speaker-volume" "@DEFAULT_AUDIO_SINK@";

  notificationAction =
    mkScript "eww-notification-action"
      [
        pkgs.coreutils
        pkgs.gawk
        pkgs.gnugrep
        pkgs.mako
        pkgs.util-linux
      ]
      ''
        ${notificationStateFunction}

        history_ids() {
          makoctl history 2>/dev/null \
            | awk '/^Notification [0-9]+:/ { id = $2; sub(/:$/, "", id); print id }'
        }

        remove_unread() {
          unread_id="$1"
          tmp_file="$(mktemp)"
          grep -Fxv "$unread_id" "$notification_unread_file" > "$tmp_file" || true
          mv "$tmp_file" "$notification_unread_file"
        }

        notification_state_setup

        while :; do
          has_unread="false"
          restore_id=""
          restore_is_unread="false"
          {
            flock 9
            current_history="$(history_ids)"
            restore_id="$(printf '%s\n' "$current_history" | awk 'NF { print; exit }')"
            while IFS= read -r unread_id; do
              [ -n "$unread_id" ] || continue
              if printf '%s\n' "$current_history" | grep -Fxq "$unread_id"; then
                has_unread="true"
                if [ "$restore_id" = "$unread_id" ]; then
                  restore_is_unread="true"
                fi
                break
              fi
            done < "$notification_unread_file"
          } 9>"$notification_lock_file"

          [ "$has_unread" = "true" ] || break
          [ -n "$restore_id" ] || break
          makoctl restore 2>/dev/null || break

          if [ "$restore_is_unread" = "true" ]; then
            {
              flock 9
              remove_unread "$restore_id"
            } 9>"$notification_lock_file"
          fi
        done

        ${pollEww} notifications
      '';

  notificationMarkRead =
    mkScript "eww-notification-mark-read"
      [
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.util-linux
      ]
      ''
        ${notificationStateFunction}

        notification_id="''${1:-''${id:-}}"
        [ -n "$notification_id" ] || exit 0

        notification_state_setup
        {
          flock 9
          tmp_file="$(mktemp)"
          grep -Fxv "$notification_id" "$notification_unread_file" > "$tmp_file" || true
          mv "$tmp_file" "$notification_unread_file"
        } 9>"$notification_lock_file"
      '';

  notificationMarkUnread =
    mkScript "eww-notification-mark-unread"
      [
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.util-linux
      ]
      ''
        ${notificationStateFunction}

        notification_id="''${1:-''${id:-}}"
        [ -n "$notification_id" ] || exit 0

        notification_state_setup
        {
          flock 9
          tmp_file="$(mktemp)"
          grep -Fxv "$notification_id" "$notification_unread_file" > "$tmp_file" || true
          printf '%s\n' "$notification_id" >> "$tmp_file"
          sort -n -u "$tmp_file" > "$notification_unread_file"
          rm -f "$tmp_file"
        } 9>"$notification_lock_file"
      '';

  openPavucontrol = mkScript "eww-open-pavucontrol" [ pkgs.pavucontrol ] ''
    pavucontrol >/dev/null 2>&1 &
  '';

  inherit pollEww;
  toggleMic =
    mkScript "eww-toggle-mic"
      [
        pkgs.eww
        pkgs.wireplumber
      ]
      ''
        wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
        ${pollEww} audio
      '';

  toggleSpeaker =
    mkScript "eww-toggle-speaker"
      [
        pkgs.eww
        pkgs.wireplumber
      ]
      ''
        wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
        ${pollEww} audio
      '';

  inherit reloadEww;

  watchBars =
    mkScript "watch-eww-bars"
      (
        commonInputs
        ++ [
          pkgs.gnused
        ]
      )
      ''
        sanitize_id() {
          printf '%s' "$1" | tr -c '[:alnum:]_' '_'
        }

        current_outputs() {
          niri msg -j outputs 2>/dev/null \
            | jq -r 'if type == "array" then .[]?.name else keys[] end' 2>/dev/null \
            | sort
        }

        wait_for_eww() {
          for _ in $(seq 1 100); do
            if eww --config ${ewwConfigDir} ping >/dev/null 2>&1; then
              return 0
            fi
            sleep 0.1
          done
          return 1
        }

        open_bars() {
          outputs="$(current_outputs)"
          if [ -z "$outputs" ]; then
            outputs="0"
          fi

          if [ "$outputs" = "''${last_outputs:-}" ]; then
            return 0
          fi
          last_outputs="$outputs"

          eww --config ${ewwConfigDir} close-all >/dev/null 2>&1 || true

          while IFS= read -r output; do
            [ -n "$output" ] || continue
            id="$(sanitize_id "$output")"
            (cd ${ewwConfigDir} && eww --config ${ewwConfigDir} open --id "bar_$id" --arg "monitor=$output" bar) >/dev/null 2>&1 || true
          done <<< "$outputs"
        }

        wait_for_eww
        last_outputs=""
        open_bars

        niri msg event-stream 2>/dev/null | while IFS= read -r _; do
          open_bars
        done
      '';
}
