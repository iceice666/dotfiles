{ mkScript, pkgs, ... }:
{
  perfStatus =
    mkScript "eww-perf-status"
      (with pkgs; [
        coreutils
        gawk
        jq
      ])
      ''
        runtime_dir="''${XDG_RUNTIME_DIR:-/tmp}"
        net_cache="$runtime_dir/eww-net"
        cpu_cache="$runtime_dir/eww-cpu"
        iface="wlp192s0"

        if [ ! -d "/sys/class/net/$iface" ]; then
          iface="$(
            for candidate in /sys/class/net/*; do
              name="$(basename "$candidate")"
              if [ "$name" != "lo" ]; then
                printf '%s' "$name"
                break
              fi
            done
          )"
        fi
        [ -n "$iface" ] || iface="lo"

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
        rx_delta=$((rx - old_rx))
        tx_delta=$((tx - old_tx))
        [ "$rx_delta" -lt 0 ] && rx_delta=0
        [ "$tx_delta" -lt 0 ] && tx_delta=0
        down_kib=$((rx_delta / 1024 / elapsed))
        up_kib=$((tx_delta / 1024 / elapsed))

        format_rate() {
          value="$1"
          if [ "$value" -ge 1024 ]; then
            awk -v value="$value" 'BEGIN { printf "%.1fM", value / 1024 }'
          else
            printf '%sK' "$value"
          fi
        }

        ram="$(
          awk '
            /MemTotal:/ { total = $2 }
            /MemAvailable:/ { available = $2 }
            END {
              if (total > 0) {
                printf "%.0f%%", (total - available) * 100 / total
              } else {
                printf "--"
              }
            }
          ' /proc/meminfo
        )"

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

        jq -cn \
          --arg cpu "$cpu" \
          --arg ram "$ram" \
          --arg gpu "$gpu" \
          --arg up "$(format_rate "$up_kib")" \
          --arg down "$(format_rate "$down_kib")" \
          '{ cpu: $cpu, ram: $ram, gpu: $gpu, up: $up, down: $down }'
      '';
}
