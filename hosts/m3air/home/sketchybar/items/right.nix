# Right-side bar items: datetime, battery, input method, network, memory, CPU
{
  colors,
  battery,
  inputMethod,
  network,
  mem,
  cpu,
}:

''
  # ── Right: Date / Time ──────────────────────────────────────────────────────
  sketchybar \
    --add item datetime right \
    --set datetime \
      update_freq=30 \
      icon="󰃭" \
      icon.font="Hack Nerd Font:Regular:14.0" \
      script="sketchybar --set datetime label=\"\$(date '+%Y-%m-%d %H:%M')\""

  # ── Right: Battery ──────────────────────────────────────────────────────────
  sketchybar \
    --add item battery right \
    --set battery \
      update_freq=60 \
      icon.font="Hack Nerd Font:Regular:14.0" \
      script="${battery}" \
    --subscribe battery power_source_change system_woke

  # ── Right: Input method ─────────────────────────────────────────────────────
  sketchybar \
    --add item input_method right \
    --set input_method \
      update_freq=3 \
      icon="󰌌" \
      icon.font="Hack Nerd Font:Regular:14.0" \
      script="${inputMethod}"

  # ── Right: Network ──────────────────────────────────────────────────────────
  sketchybar \
    --add item network right \
    --set network \
      update_freq=3 \
      icon="󰛳" \
      icon.font="Hack Nerd Font:Regular:14.0" \
      label="↑0B ↓0B" \
      script="${network}"

  # ── Right: Memory ───────────────────────────────────────────────────────────
  sketchybar \
    --add item mem right \
    --set mem \
      update_freq=5 \
      icon="󰍛" \
      icon.font="Hack Nerd Font:Regular:14.0" \
      label="0%" \
      click_script="sketchybar --set mem popup.drawing=toggle; ${mem.popup}" \
      script="${mem.mem}"

  # mem popup: top-10 memory consumers
  sketchybar --add bracket mem_popup_bracket mem
  sketchybar --set mem popup.background.color=${colors.bg1}
  sketchybar --set mem popup.background.border_width=1
  sketchybar --set mem popup.background.border_color=${colors.border}
  sketchybar --set mem popup.background.corner_radius=8

  for i in 1 2 3 4 5 6 7 8 9 10; do
    sketchybar \
      --add item "mem_top_$i" popup.mem \
      --set "mem_top_$i" \
        icon.font="SF Pro:Semibold:11.0" \
        icon.width=50 \
        icon.align=right \
        label.font="SF Pro:Regular:11.0" \
        label.padding_right=8 \
        background.drawing=off \
        label="—"
  done

  # ── Right: CPU ──────────────────────────────────────────────────────────────
  sketchybar \
    --add item cpu right \
    --set cpu \
      update_freq=3 \
      icon="󰻠" \
      icon.font="Hack Nerd Font:Regular:14.0" \
      label="0%" \
      click_script="sketchybar --set cpu popup.drawing=toggle; ${cpu.popup}" \
      script="${cpu.cpu}"

  # cpu popup: top-10 CPU consumers
  sketchybar --add bracket cpu_popup_bracket cpu
  sketchybar --set cpu popup.background.color=${colors.bg1}
  sketchybar --set cpu popup.background.border_width=1
  sketchybar --set cpu popup.background.border_color=${colors.border}
  sketchybar --set cpu popup.background.corner_radius=8

  for i in 1 2 3 4 5 6 7 8 9 10; do
    sketchybar \
      --add item "cpu_top_$i" popup.cpu \
      --set "cpu_top_$i" \
        icon.font="SF Pro:Semibold:11.0" \
        icon.width=50 \
        icon.align=right \
        label.font="SF Pro:Regular:11.0" \
        label.padding_right=8 \
        background.drawing=off \
        label="—"
  done
''
