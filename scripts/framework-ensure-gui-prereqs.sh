#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "This helper is only for the Framework Arch Linux host." >&2
  exit 1
fi

if ! command -v pacman >/dev/null 2>&1; then
  echo "pacman not found; this helper expects Arch Linux." >&2
  exit 1
fi

packages=(
  bluez
  bluez-utils
  dbus
  fprintd
  gdm
  networkmanager
  pipewire
  pipewire-pulse
  polkit
  wireplumber
)

sudo -v
sudo pacman -S --needed "${packages[@]}"

sudo systemctl daemon-reload
sudo systemctl enable --now NetworkManager.service bluetooth.service gdm.service
sudo systemctl start fprintd.service

if systemctl --user show-environment >/dev/null 2>&1; then
  systemctl --user daemon-reload
  systemctl --user enable --now pipewire.service pipewire-pulse.service wireplumber.service
else
  cat >&2 <<'EOF'
User systemd is not available in this shell.
After logging into a normal user session, run:
  systemctl --user enable --now pipewire.service pipewire-pulse.service wireplumber.service
EOF
fi
