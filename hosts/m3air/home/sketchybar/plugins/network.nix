# Network throughput plugin
{ pkgs }:

let
  # Formats bytes/s to human-readable (e.g. 1.2M, 304K, 512B)
  fmtBytes = pkgs.writeShellScript "sketchybar-fmt-bytes" ''
    bytes=$1
    if [ "$bytes" -ge 1048576 ]; then
      printf "%.1fM" "$(echo "scale=1; $bytes/1048576" | bc)"
    elif [ "$bytes" -ge 1024 ]; then
      printf "%.0fK" "$(echo "scale=0; $bytes/1024" | bc)"
    else
      printf "%dB" "$bytes"
    fi
  '';
in

pkgs.writeShellScript "sketchybar-network" ''
  #!/usr/bin/env bash
  CACHE_FILE="/tmp/sketchybar_net_cache"
  # Get primary interface (default route)
  IFACE=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
  [ -z "$IFACE" ] && IFACE="en0"

  NOW=$(date +%s%N)
  BYTES_IN=$(netstat -ib 2>/dev/null \
    | awk -v iface="$IFACE" '$1==iface && $3~/[0-9]+\.[0-9]+\.[0-9]+/ {print $7; exit}')
  BYTES_OUT=$(netstat -ib 2>/dev/null \
    | awk -v iface="$IFACE" '$1==iface && $3~/[0-9]+\.[0-9]+\.[0-9]+/ {print $10; exit}')

  [ -z "$BYTES_IN"  ] && BYTES_IN=0
  [ -z "$BYTES_OUT" ] && BYTES_OUT=0

  if [ -f "$CACHE_FILE" ]; then
    read -r PREV_TIME PREV_IN PREV_OUT < "$CACHE_FILE"
    ELAPSED=$(( (NOW - PREV_TIME) / 1000000000 ))
    [ "$ELAPSED" -le 0 ] && ELAPSED=1
    DELTA_IN=$(( (BYTES_IN  - PREV_IN)  / ELAPSED ))
    DELTA_OUT=$(( (BYTES_OUT - PREV_OUT) / ELAPSED ))
    [ "$DELTA_IN"  -lt 0 ] && DELTA_IN=0
    [ "$DELTA_OUT" -lt 0 ] && DELTA_OUT=0
    IN_STR=$("${fmtBytes}" "$DELTA_IN")
    OUT_STR=$("${fmtBytes}" "$DELTA_OUT")
    sketchybar --set network label="↑''${OUT_STR} ↓''${IN_STR}"
  fi
  echo "$NOW $BYTES_IN $BYTES_OUT" > "$CACHE_FILE"
''
