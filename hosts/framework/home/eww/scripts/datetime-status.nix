{ mkScript, pkgs, ... }:
{
  datetimeStatus = mkScript "eww-datetime-status" [ pkgs.coreutils ] ''
    weekday="$(date +%u)"
    case "$weekday" in
      1) weekday="一" ;;
      2) weekday="二" ;;
      3) weekday="三" ;;
      4) weekday="四" ;;
      5) weekday="五" ;;
      6) weekday="六" ;;
      7) weekday="日" ;;
    esac
    printf '%s月%s日 周%s %s' "$(date +%-m)" "$(date +%-d)" "$weekday" "$(date +%H:%M)"
  '';
}
