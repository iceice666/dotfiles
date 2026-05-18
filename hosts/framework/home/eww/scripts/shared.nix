{ pkgs }:
let
  inherit (pkgs) lib;
in
{
  inherit lib;
  inherit pkgs;

  mkScript =
    name: runtimeInputs: text:
    lib.getExe (
      pkgs.writeShellApplication {
        inherit name runtimeInputs text;
      }
    );

  commonInputs = with pkgs; [
    coreutils
    eww
    gawk
    gnugrep
    jq
    niri
  ];

  themeColorFunction = ''
    theme_color() {
      name="$1"
      fallback="$2"
      theme_file="$HOME/.config/eww/theme.scss"
      if [ -r "$theme_file" ]; then
        value="$(
          awk -v key="\$$name" '
            BEGIN { FS = ":[[:space:]]*|;" }
            $1 == key { print $2; exit }
          ' "$theme_file"
        )"
        if [ -n "$value" ]; then
          printf '%s' "$value"
          return
        fi
      fi
      printf '%s' "$fallback"
    }
  '';

  notificationStateFunction = ''
    notification_state_dir="''${XDG_RUNTIME_DIR:-/tmp}/eww-notifications"
    notification_unread_file="$notification_state_dir/unread"
    notification_lock_file="$notification_state_dir/unread.lock"

    notification_state_setup() {
      mkdir -p "$notification_state_dir"
      touch "$notification_unread_file"
    }
  '';
}
