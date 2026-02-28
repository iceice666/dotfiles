# Memory usage + popup plugin scripts
{ pkgs }:

{
  mem = pkgs.writeShellScript "sketchybar-mem" ''
    #!/usr/bin/env bash
    # Parse vm_stat for memory usage
    PAGE_SIZE=$(pagesize)
    vm=$(vm_stat)
    pages_active=$(echo "$vm"      | awk '/Pages active/    {gsub(/\./,""); print $3}')
    pages_wired=$(echo "$vm"       | awk '/Pages wired/     {gsub(/\./,""); print $4}')
    pages_compressed=$(echo "$vm"  | awk '/Pages occupied by compressor/ {gsub(/\./,""); print $5}')

    TOTAL_MEM=$(sysctl -n hw.memsize)
    USED=$(( (pages_active + pages_wired + pages_compressed) * PAGE_SIZE ))
    PCT=$(echo "scale=0; $USED * 100 / $TOTAL_MEM" | bc)
    sketchybar --set mem label="''${PCT}%"
  '';

  popup = pkgs.writeShellScript "sketchybar-mem-popup" ''
    #!/usr/bin/env bash
    i=1
    while IFS= read -r line; do
      NAME=$(echo "$line" | awk '{print $11}' | xargs basename 2>/dev/null)
      PCT=$(echo "$line" | awk '{printf "%.1f%%", $4}')
      sketchybar --set "mem_top_$i" label="$NAME" icon="$PCT"
      i=$((i+1))
    done < <(ps aux -m | awk 'NR>1 && $4>0' | sort -k4 -rn | head -10)
  '';
}
