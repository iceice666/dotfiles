# CPU usage + popup plugin scripts
{ pkgs }:

{
  cpu = pkgs.writeShellScript "sketchybar-cpu" ''
    #!/usr/bin/env bash
    CPU=$(top -l 1 -s 0 | awk '/CPU usage/ {gsub(/%/,""); printf "%.0f", $3+$5}')
    sketchybar --set cpu label="$CPU%"
  '';

  popup = pkgs.writeShellScript "sketchybar-cpu-popup" ''
    #!/usr/bin/env bash
    # Refresh popup items with current top-10 CPU consumers
    i=1
    while IFS= read -r line; do
      NAME=$(echo "$line" | awk '{print $11}' | xargs basename 2>/dev/null)
      PCT=$(echo "$line" | awk '{printf "%.1f%%", $3}')
      sketchybar --set "cpu_top_$i" label="$NAME" icon="$PCT"
      i=$((i+1))
    done < <(ps aux -r | awk 'NR>1 && $3>0' | sort -k3 -rn | head -10)
  '';
}
