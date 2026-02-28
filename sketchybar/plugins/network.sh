#!/usr/bin/env sh

STATE_FILE="/tmp/sketchybar_network_stats"
now="$(date +%s)"

stats="$(netstat -ib 2>/dev/null | awk 'NR > 1 && $1 !~ /^lo/ && $7 ~ /^[0-9]+$/ && $10 ~ /^[0-9]+$/ {inb += $7; outb += $10} END {print inb, outb}')"
in_bytes="$(echo "$stats" | awk '{print $1}')"
out_bytes="$(echo "$stats" | awk '{print $2}')"

if [ -z "$in_bytes" ] || [ -z "$out_bytes" ]; then
  sketchybar --set "$NAME" label="--"
  exit 0
fi

if [ -f "$STATE_FILE" ]; then
  last_t="$(awk '{print $1}' "$STATE_FILE")"
  last_in="$(awk '{print $2}' "$STATE_FILE")"
  last_out="$(awk '{print $3}' "$STATE_FILE")"
  dt=$((now - last_t))
else
  dt=0
fi

echo "$now $in_bytes $out_bytes" > "$STATE_FILE"

if [ "$dt" -le 0 ] || [ -z "$last_in" ] || [ -z "$last_out" ]; then
  sketchybar --set "$NAME" label="--"
  exit 0
fi

down_bps=$(((in_bytes - last_in) / dt))
up_bps=$(((out_bytes - last_out) / dt))

human_rate() {
  value="$1"
  if [ "$value" -ge 1048576 ]; then
    echo "$(echo "scale=1; $value/1048576" | bc)M/s"
  elif [ "$value" -ge 1024 ]; then
    echo "$(echo "scale=1; $value/1024" | bc)K/s"
  else
    echo "${value}B/s"
  fi
}

label="↓ $(human_rate "$down_bps") ↑ $(human_rate "$up_bps")"
sketchybar --set "$NAME" label="$label"
