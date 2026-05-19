{
  mkScript,
  themeColorFunction,
  icons,
  pkgs,
  ...
}:
let
  audioStatusText = ''
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
          if (volume < 0) volume = 0
          if (volume > 100) volume = 100
          printf "%s %s\n", volume, muted ? "1" : "0"
        }
      '
    }

    device_description() {
      wpctl inspect "$1" 2>/dev/null | awk -F ' = ' '
        /node.description/ {
          value = $2
          gsub(/^"|"$/, "", value)
          print value
          found = 1
          exit
        }
        /node.name/ && fallback == "" {
          fallback = $2
          gsub(/^"|"$/, "", fallback)
        }
        END {
          if (!found && fallback != "") print fallback
        }
      '
    }

    read -r speaker_value speaker_muted < <(parse_volume @DEFAULT_AUDIO_SINK@)
    read -r mic_value mic_muted < <(parse_volume @DEFAULT_AUDIO_SOURCE@)

    speaker_device="$(device_description @DEFAULT_AUDIO_SINK@)"
    mic_device="$(device_description @DEFAULT_AUDIO_SOURCE@)"
    [ -n "$speaker_device" ] || speaker_device="Unknown output"
    [ -n "$mic_device" ] || mic_device="Unknown input"

    speaker_icon="${icons.speakerHigh}"
    speaker_color="$foreground"
    speaker_class="audio-control speaker"
    speaker_muted_json=false
    if [ "$speaker_muted" = "1" ]; then
      speaker_icon="${icons.speakerMuted}"
      speaker_color="$foreground_dim"
      speaker_class="$speaker_class muted"
      speaker_muted_json=true
      speaker_text="Output muted ($speaker_value%) - $speaker_device"
    elif [ "$speaker_value" -eq 0 ]; then
      speaker_icon="${icons.speakerMuted}"
      speaker_color="$foreground_dim"
      speaker_text="Output 0% - $speaker_device"
    elif [ "$speaker_value" -lt 45 ]; then
      speaker_icon="${icons.speakerLow}"
      speaker_text="Output $speaker_value% - $speaker_device"
    else
      speaker_text="Output $speaker_value% - $speaker_device"
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
      mic_text="Input muted ($mic_value%) - $mic_device"
    elif [ "$mic_value" -eq 0 ]; then
      mic_icon="${icons.micMuted}"
      mic_color="$foreground_dim"
      mic_text="Input 0% - $mic_device"
    else
      mic_text="Input $mic_value% - $mic_device"
    fi

    jq -cn \
      --argjson speaker_value "$speaker_value" \
      --argjson speaker_muted "$speaker_muted_json" \
      --arg speaker_class "$speaker_class" \
      --arg speaker_icon "$speaker_icon" \
      --arg speaker_text "$speaker_text" \
      --arg speaker_color "$speaker_color" \
      --arg speaker_device "$speaker_device" \
      --argjson mic_value "$mic_value" \
      --argjson mic_muted "$mic_muted_json" \
      --arg mic_class "$mic_class" \
      --arg mic_icon "$mic_icon" \
      --arg mic_text "$mic_text" \
      --arg mic_color "$mic_color" \
      --arg mic_device "$mic_device" \
      '{
        speaker_value: $speaker_value,
        speaker_muted: $speaker_muted,
        speaker_class: $speaker_class,
        speaker_icon: $speaker_icon,
        speaker_text: $speaker_text,
        speaker_color: $speaker_color,
        speaker_device: $speaker_device,
        mic_value: $mic_value,
        mic_muted: $mic_muted,
        mic_class: $mic_class,
        mic_icon: $mic_icon,
        mic_text: $mic_text,
        mic_color: $mic_color,
        mic_device: $mic_device
      }'
  '';
in
{
  audioStatus = mkScript "eww-audio-status" (with pkgs; [
    gawk
    jq
    wireplumber
  ]) audioStatusText;

  audioStatusListen =
    mkScript "eww-audio-status-listen"
      (with pkgs; [
        gawk
        jq
        pulseaudio
        wireplumber
      ])
      ''
        emit_audio_status() {
          ${audioStatusText}
        }

        emit_audio_status

        while :; do
          pactl subscribe 2>/dev/null | while IFS= read -r event; do
            case "$event" in
              *" on card"*|*" on server"*|*" on sink"*|*" on source"*)
                emit_audio_status
                ;;
            esac
          done
          sleep 1
          emit_audio_status
        done
      '';
}
