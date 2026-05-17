{ pkgs, ewwConfigDir }:

let
  focusWindow = pkgs.writeShellScript "eww-focus-window" ''
    if [ -n "''${1:-}" ]; then
      ${pkgs.niri}/bin/niri msg action focus-window --id "$1"
    fi
  '';

  niriState = pkgs.writeShellScript "eww-niri-state" ''
    snapshot() {
      windows="$(${pkgs.niri}/bin/niri msg -j windows 2>/dev/null || printf '[]')"
      workspaces="$(${pkgs.niri}/bin/niri msg -j workspaces 2>/dev/null || printf '[]')"
      outputs="$(${pkgs.niri}/bin/niri msg -j outputs 2>/dev/null || printf '{}')"

      ${pkgs.jq}/bin/jq -cn \
        --argjson windows "$windows" \
        --argjson workspaces "$workspaces" \
        --argjson outputs "$outputs" '
          def workspaceLabel:
            (.name // (.idx // .index // .id | tostring));

          def outputNames:
            if ($outputs | type) == "array" then
              [ $outputs[] | .name // .output // empty ]
            elif ($outputs | type) == "object" then
              [ $outputs | keys[] ]
            else
              []
            end;

          def workspaceOutput:
            .output // .output_name // .monitor // "";

          def visibleWorkspace:
            (.is_active // .active // .is_focused // .focused // false);

          def focusedWindow:
            first($windows[]? | select(.is_focused // .focused // false));

          def windowText:
            .title // .app_id // "App";

          (outputNames) as $outputNames |
          (if ($outputNames | length) > 0 then
            $outputNames
          else
            [ $workspaces[]? | workspaceOutput ] | unique | map(select(. != ""))
          end) as $monitors |
          {
            focused_title: ((focusedWindow | windowText) // "Desktop"),
            groups: [
              $monitors[] as $monitor |
              {
                monitor: $monitor,
                workspaces: [
                  $workspaces[]?
                  | select(workspaceOutput == $monitor)
                  | . as $workspace
                  | {
                    label: ($workspace | workspaceLabel),
                    class: (if ($workspace | visibleWorkspace) then "workspace visible" else "workspace dim" end),
                    windows: [
                      $windows[]?
                      | select((.workspace_id // .workspace // -1) == ($workspace.id // -2))
                      | {
                        id,
                        text: (.app_id // .title // "App"),
                        title: (.title // .app_id // "App"),
                        class: (
                          if (.is_focused // .focused // false) then
                            "app focused"
                          elif ($workspace | visibleWorkspace) then
                            "app visible"
                          else
                            "app dim"
                          end
                        )
                      }
                    ]
                  }
                ]
              }
            ]
          }
        '
    }

    snapshot
    ${pkgs.niri}/bin/niri msg event-stream 2>/dev/null | while IFS= read -r _; do
      snapshot
    done
  '';

  mediaStatus = pkgs.writeShellScript "eww-media-status" ''
    if ! ${pkgs.playerctl}/bin/playerctl status >/dev/null 2>&1; then
      printf 'No media'
      exit 0
    fi

    status="$(${pkgs.playerctl}/bin/playerctl status 2>/dev/null || true)"
    text="$(${pkgs.playerctl}/bin/playerctl metadata --format '{{artist}} - {{title}}' 2>/dev/null || true)"
    if [ -z "$text" ] || [ "$text" = " - " ]; then
      text="$status"
    fi
    printf '%s' "$text"
  '';

  perfStatus = pkgs.writeShellScript "eww-perf-status" ''
    runtime_dir="''${XDG_RUNTIME_DIR:-/tmp}"
    net_cache="$runtime_dir/eww-net.wlp192s0"
    cpu_cache="$runtime_dir/eww-cpu"
    iface="wlp192s0"

    rx_path="/sys/class/net/$iface/statistics/rx_bytes"
    tx_path="/sys/class/net/$iface/statistics/tx_bytes"
    rx=0
    tx=0
    [ -r "$rx_path" ] && rx="$(cat "$rx_path")"
    [ -r "$tx_path" ] && tx="$(cat "$tx_path")"
    now="$(date +%s)"

    old_rx="$rx"
    old_tx="$tx"
    old_now="$now"
    if [ -r "$net_cache" ]; then
      read -r old_now old_rx old_tx < "$net_cache"
    fi
    printf '%s %s %s\n' "$now" "$rx" "$tx" > "$net_cache"

    elapsed=$((now - old_now))
    [ "$elapsed" -lt 1 ] && elapsed=1
    down_kib=$(((rx - old_rx) / 1024 / elapsed))
    up_kib=$(((tx - old_tx) / 1024 / elapsed))

    wifi="$(${pkgs.networkmanager}/bin/nmcli -t -f IN-USE,SIGNAL dev wifi list ifname "$iface" 2>/dev/null | ${pkgs.gawk}/bin/awk -F: '$1 == "*" { print $2; exit }')"
    [ -z "$wifi" ] && wifi="--"

    ram="$(${pkgs.gawk}/bin/awk '
      /MemTotal:/ { total = $2 }
      /MemAvailable:/ { available = $2 }
      END {
        if (total > 0) {
          printf "%.0f%%", (total - available) * 100 / total
        } else {
          printf "--"
        }
      }
    ' /proc/meminfo)"

    read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
    idle_all=$((idle + iowait))
    total=$((user + nice + system + idle + iowait + irq + softirq + steal))
    old_total="$total"
    old_idle="$idle_all"
    if [ -r "$cpu_cache" ]; then
      read -r old_total old_idle < "$cpu_cache"
    fi
    printf '%s %s\n' "$total" "$idle_all" > "$cpu_cache"
    total_delta=$((total - old_total))
    idle_delta=$((idle_all - old_idle))
    if [ "$total_delta" -gt 0 ]; then
      cpu="$(((100 * (total_delta - idle_delta)) / total_delta))%"
    else
      cpu="--"
    fi

    gpu="--"
    if [ -r /sys/class/drm/card1/device/gpu_busy_percent ]; then
      gpu="$(cat /sys/class/drm/card1/device/gpu_busy_percent)%"
    elif [ -r /sys/class/drm/card0/device/gpu_busy_percent ]; then
      gpu="$(cat /sys/class/drm/card0/device/gpu_busy_percent)%"
    fi

    printf 'NET %s%% ↓%sK ↑%sK  RAM %s  CPU %s  GPU %s' "$wifi" "$down_kib" "$up_kib" "$ram" "$cpu" "$gpu"
  '';

  bluetoothStatus = pkgs.writeShellScript "eww-bluetooth-status" ''
    powered="$(${pkgs.bluez}/bin/bluetoothctl show 2>/dev/null | ${pkgs.gawk}/bin/awk -F': ' '/Powered:/ { print $2; exit }')"
    if [ "$powered" != "yes" ]; then
      printf 'BT off'
      exit 0
    fi

    connected="$(${pkgs.bluez}/bin/bluetoothctl devices Connected 2>/dev/null | wc -l | tr -d ' ')"
    if [ "''${connected:-0}" -gt 0 ]; then
      printf 'BT %s' "$connected"
    else
      printf 'BT on'
    fi
  '';

  batteryStatus = pkgs.writeShellScript "eww-battery-status" ''
    battery=""
    for candidate in /sys/class/power_supply/BAT*; do
      if [ -d "$candidate" ]; then
        battery="$candidate"
        break
      fi
    done

    if [ -z "$battery" ]; then
      ${pkgs.jq}/bin/jq -cn '{ text: "BAT --", class: "module battery" }'
      exit 0
    fi

    capacity="--"
    status="Unknown"
    [ -r "$battery/capacity" ] && capacity="$(cat "$battery/capacity")"
    [ -r "$battery/status" ] && status="$(cat "$battery/status")"

    class="module battery"
    suffix=""
    case "$status" in
      Charging) suffix="+"; class="$class charging" ;;
      Full) suffix=""; class="$class full" ;;
      Discharging)
        if [ "$capacity" != "--" ] && [ "$capacity" -le 15 ]; then
          class="$class critical"
        elif [ "$capacity" != "--" ] && [ "$capacity" -le 30 ]; then
          class="$class warning"
        fi
        ;;
    esac

    ${pkgs.jq}/bin/jq -cn \
      --arg text "BAT $capacity%$suffix" \
      --arg class "$class" \
      '{ text: $text, class: $class }'
  '';

  audioStatus = pkgs.writeShellScript "eww-audio-status" ''
    sink="$(${pkgs.wireplumber}/bin/wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || true)"
    source="$(${pkgs.wireplumber}/bin/wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null || true)"

    speaker="$(
      printf '%s\n' "$sink" | ${pkgs.gawk}/bin/awk '
        /MUTED/ { muted = 1 }
        /Volume:/ { volume = int($2 * 100 + 0.5) }
        END {
          if (muted) print "muted";
          else if (volume != "") print volume "%";
          else print "--";
        }
      '
    )"

    mic="$(
      printf '%s\n' "$source" | ${pkgs.gawk}/bin/awk '
        /MUTED/ { muted = 1 }
        /Volume:/ { volume = int($2 * 100 + 0.5) }
        END {
          if (muted) print "muted";
          else if (volume != "") print volume "%";
          else print "--";
        }
      '
    )"

    ${pkgs.jq}/bin/jq -cn --arg speaker "$speaker" --arg mic "$mic" '{ speaker: $speaker, mic: $mic }'
  '';

  datetimeStatus = pkgs.writeShellScript "eww-datetime-status" ''
    weekday="$(date +%u)"
    case "$weekday" in
      1) weekday="一" ;;
      2) weekday="二" ;;
      3) weekday="三" ;;
      4) weekday="四" ;;
      5) weekday="五" ;;
      6) weekday="六" ;;
      7) weekday="日" ;;
    esac
    printf '%s月%s日 周%s %s' "$(date +%-m)" "$(date +%-d)" "$weekday" "$(date +%H:%M)"
  '';

  notificationsStatus = pkgs.writeShellScript "eww-notifications-status" ''
    if ${pkgs.mako}/bin/makoctl list >/dev/null 2>&1; then
      count="$(${pkgs.mako}/bin/makoctl list 2>/dev/null | ${pkgs.gnugrep}/bin/grep -c 'Notification' || true)"
      if [ "''${count:-0}" -gt 0 ]; then
        printf '通知 %s' "$count"
      else
        printf '通知'
      fi
    else
      printf '通知'
    fi
  '';

  notificationAction = pkgs.writeShellScript "eww-notification-action" ''
    ${pkgs.mako}/bin/makoctl dismiss --all 2>/dev/null || true
  '';

  launchEww = pkgs.writeShellScript "launch-eww-bars" ''
    for _ in $(${pkgs.coreutils}/bin/seq 1 50); do
      if ${pkgs.niri}/bin/niri msg -j outputs >/dev/null 2>&1; then
        break
      fi
      ${pkgs.coreutils}/bin/sleep 0.1
    done

    ${pkgs.eww}/bin/eww --config ${ewwConfigDir} daemon
    ${pkgs.eww}/bin/eww --config ${ewwConfigDir} close-all >/dev/null 2>&1 || true

    outputs="$(${pkgs.niri}/bin/niri msg -j outputs 2>/dev/null | ${pkgs.jq}/bin/jq -r 'if type == "array" then .[].name else keys[] end' 2>/dev/null || true)"
    if [ -z "$outputs" ]; then
      outputs="0"
    fi

    args=()
    for output in $outputs; do
      id="$(printf '%s' "$output" | ${pkgs.coreutils}/bin/tr -c '[:alnum:]_' '_')"
      args+=(--arg "bar_$id:monitor=$output" "bar:bar_$id")
    done

    ${pkgs.eww}/bin/eww --config ${ewwConfigDir} open-many "''${args[@]}"
  '';
in
{
  inherit
    audioStatus
    batteryStatus
    bluetoothStatus
    datetimeStatus
    focusWindow
    launchEww
    mediaStatus
    niriState
    notificationAction
    notificationsStatus
    perfStatus
    ;
}
