{ mkScript, pkgs, ... }:
{
  focusWindow = mkScript "eww-focus-window" [ pkgs.niri ] ''
    if [ -n "''${1:-}" ]; then
      niri msg action focus-window --id "$1"
    fi
  '';
}
