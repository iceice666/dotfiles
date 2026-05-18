{ mkScript, pkgs, ... }:
{
  mediaStatus = mkScript "eww-media-status" [ pkgs.playerctl ] ''
    if ! playerctl status >/dev/null 2>&1; then
      printf '%s' ""
      exit 0
    fi

    status="$(playerctl status 2>/dev/null || true)"
    text="$(playerctl metadata --format '{{artist}} - {{title}}' 2>/dev/null || true)"
    if [ -z "$text" ] || [ "$text" = " - " ]; then
      text="$status"
    fi
    printf '%s' "$text"
  '';
}
