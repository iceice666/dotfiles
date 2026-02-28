# Keyboard input method indicator plugin
{ pkgs }:

pkgs.writeShellScript "sketchybar-input-method" ''
  #!/usr/bin/env bash
  # Read current keyboard input source via defaults
  SOURCE=$(defaults read ~/Library/Preferences/com.apple.HIToolbox.plist \
    AppleSelectedInputSources 2>/dev/null \
    | awk -F'"' '/"KeyboardLayout Name"/{print $4; exit}')

  case "$SOURCE" in
    ABC|"U.S."|"US"|"") LABEL="EN" ;;
    *Chinese*Simplified*)  LABEL="ZH" ;;
    *Chinese*Traditional*) LABEL="ZH" ;;
    *Japanese*)            LABEL="JP" ;;
    *Korean*)              LABEL="KO" ;;
    *French*)              LABEL="FR" ;;
    *German*)              LABEL="DE" ;;
    *Spanish*)             LABEL="ES" ;;
    *)
      # Try to grab first 2 uppercase chars from name
      LABEL=$(echo "$SOURCE" | sed 's/[^A-Za-z]//g' | cut -c1-2 | tr '[:lower:]' '[:upper:]')
      [ -z "$LABEL" ] && LABEL="??"
      ;;
  esac
  sketchybar --set input_method label="$LABEL"
''
