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

post_switch="$HOME/.nix-profile/bin/framework-post-switch"

if [[ ! -x "$post_switch" ]]; then
  cat >&2 <<EOF
Generated post-switch helper is not installed yet:
  $post_switch

Run the Framework Home Manager switch first:
  just framework-rebuild
EOF
  exit 1
fi

exec "$post_switch"
