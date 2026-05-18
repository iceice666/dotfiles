{
  mkScript,
  themeColorFunction,
  icons,
  pkgs,
  ...
}:
{
  audioStatus =
    mkScript "eww-audio-status"
      (with pkgs; [
        gawk
        jq
        wireplumber
      ])
      ''
        ${themeColorFunction}

        foreground="$(theme_color foreground '#e5e5e5')"
        foreground_dim="$(theme_color foregroundDim '#a3a3a3')"

        read_volume() {
          device="$1"
          wpctl get-volume "$device" 2>/dev/null || printf 'Volume: 0 [MUTED]\n'
        }

        parse_volume() {
          read_volume "$1" | awk '
            /MUTED/ { muted = 1 }
            /Volume:/ { volume = int($2 * 100 + 0.5) }
            END {
              if (volume == "") volume = 0
              printf "%s %s\n", volume, muted ? "1" : "0"
            }
          '
        }

        read -r speaker_value speaker_muted < <(parse_volume @DEFAULT_AUDIO_SINK@)
        read -r mic_value mic_muted < <(parse_volume @DEFAULT_AUDIO_SOURCE@)

        speaker_icon="${icons.speakerHigh}"
        speaker_color="$foreground"
        speaker_class="audio-control speaker"
        speaker_muted_json=false
        if [ "$speaker_muted" = "1" ]; then
          speaker_icon="${icons.speakerMuted}"
          speaker_color="$foreground_dim"
          speaker_class="$speaker_class muted"
          speaker_muted_json=true
          speaker_text="Speaker muted ($speaker_value%)"
        elif [ "$speaker_value" -eq 0 ]; then
          speaker_icon="${icons.speakerMuted}"
          speaker_color="$foreground_dim"
          speaker_text="Speaker 0%"
        elif [ "$speaker_value" -lt 45 ]; then
          speaker_icon="${icons.speakerLow}"
          speaker_text="Speaker $speaker_value%"
        else
          speaker_text="Speaker $speaker_value%"
        fi

        mic_icon="${icons.micActive}"
        mic_color="$foreground"
        mic_class="audio-control mic"
        mic_muted_json=false
        if [ "$mic_muted" = "1" ]; then
          mic_icon="${icons.micMuted}"
          mic_color="$foreground_dim"
          mic_class="$mic_class muted"
          mic_muted_json=true
          mic_text="Microphone muted ($mic_value%)"
        elif [ "$mic_value" -eq 0 ]; then
          mic_icon="${icons.micMuted}"
          mic_color="$foreground_dim"
          mic_text="Microphone 0%"
        else
          mic_text="Microphone $mic_value%"
        fi

        jq -cn \
          --argjson speaker_value "$speaker_value" \
          --argjson speaker_muted "$speaker_muted_json" \
          --arg speaker_class "$speaker_class" \
          --arg speaker_icon "$speaker_icon" \
          --arg speaker_text "$speaker_text" \
          --arg speaker_color "$speaker_color" \
          --argjson mic_value "$mic_value" \
          --argjson mic_muted "$mic_muted_json" \
          --arg mic_class "$mic_class" \
          --arg mic_icon "$mic_icon" \
          --arg mic_text "$mic_text" \
          --arg mic_color "$mic_color" \
          '{
            speaker_value: $speaker_value,
            speaker_muted: $speaker_muted,
            speaker_class: $speaker_class,
            speaker_icon: $speaker_icon,
            speaker_text: $speaker_text,
            speaker_color: $speaker_color,
            mic_value: $mic_value,
            mic_muted: $mic_muted,
            mic_class: $mic_class,
            mic_icon: $mic_icon,
            mic_text: $mic_text,
            mic_color: $mic_color
          }'
      '';
}
