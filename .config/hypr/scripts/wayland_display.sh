# Import the WAYLAND_DISPLAY env var from sway into the systemd user session.
dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=Hyprland


# sleep 1
# killall xdg-desktop-portal-hyprland
# killall xdg-desktop-portal-wlr
# killall xdg-desktop-portal
# /usr/lib/xdg-desktop-portal-hyprland &
# sleep 2
# /usr/lib/xdg-desktop-portal &

# Stop any services that are running, so that they receive the new env var when they restart.
systemctl --user stop pipewire wireplumber xdg-desktop-portal xdg-desktop-portal-hyprland
systemctl --user start wireplumber
