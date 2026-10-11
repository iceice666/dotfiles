set -euo pipefail
kind=${1:-}
shift || exit 2
case "$kind" in
  speaker|mic)
    case "${1:-}" in
      up|down)
        [ "$kind" = speaker ] && [ "$#" -eq 1 ] || exit 2
        snapshot=$(@shellState@ --config-file @shellStateConfig@ audio volume "$kind" "$1" --step 0.05)
        ;;
      toggle)
        [ "$#" -eq 1 ] || exit 2
        snapshot=$(@shellState@ --config-file @shellStateConfig@ audio toggle "$kind")
        ;;
      *) exit 2 ;;
    esac
    ;;
  brightness)
    [ "$#" -eq 1 ] || exit 2
    case "$1" in
      up) amount='+10%' ;;
      down) amount='10%-' ;;
      *) exit 2 ;;
    esac
    @brightnessctl@ --class=backlight set "$amount" >/dev/null
    snapshot=$(@shellState@ --config-file @shellStateConfig@ refresh brightness)
    ;;
  *) exit 2 ;;
esac
# Device actions still work while the UI is absent; delivery is best-effort.
@timeout@ --kill-after=1 1 @ags@ request osd "$kind" "$snapshot" >/dev/null 2>&1 || :
