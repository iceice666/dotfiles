#!/usr/bin/env sh
# bootstrap.sh — Clone dotfiles via HTTPS, then switch remote to SSH.
#
# Usage:
#   curl -fsSL https://code.justaslime.dev/justaslime/dotfiles/raw/branch/main/scripts/bootstrap.sh | sh
#
# What it does:
#   1. Clones the repo to ~/dotfiles over HTTPS (no SSH key needed yet).
#   2. Reconfigures the 'origin' remote to the SSH URL.
#   3. Prints next steps for each host.

set -e

# ── Dependency checks ────────────────────────────────────────────────────────

missing=""
for cmd in git just; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    missing="$missing $cmd"
  fi
done

if [ -n "$missing" ]; then
  echo "Error: the following required tools are not installed:$missing"
  echo ""
  echo "  git  — https://git-scm.com/downloads"
  echo "  just — https://just.systems/man/en/packages.html"
  exit 1
fi

HTTPS_URL="https://code.justaslime.dev/justaslime/dotfiles.git"
SSH_URL="ssh://git@justaslime.dev/justaslime/dotfiles.git"
DEST="$HOME/dotfiles"

# ── Clone ────────────────────────────────────────────────────────────────────

if [ -d "$DEST/.git" ]; then
  echo "dotfiles already present at $DEST — skipping clone."
else
  echo "Cloning dotfiles into $DEST ..."
  git clone "$HTTPS_URL" "$DEST"
fi

# ── Reconfigure remote to SSH ────────────────────────────────────────────────

cd "$DEST"

current=$(git remote get-url origin 2>/dev/null || echo "")
if [ "$current" = "$SSH_URL" ]; then
  echo "Remote 'origin' is already set to SSH URL — nothing to do."
else
  echo "Switching remote 'origin' to SSH URL ..."
  git remote set-url origin "$SSH_URL"
  echo "Remote 'origin' -> $SSH_URL"
fi

# ── Next steps ───────────────────────────────────────────────────────────────

cat <<'EOF'

Done! Dotfiles are at ~/dotfiles.

Next steps depend on your machine:

  M3 Air (macOS)
    # install Lix
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.lix.systems/lix | sh -s -- install
    # install Homebrew
    just m3air-homebrew
    # build & activate
    just m3air-rebuild

  Framework (Void Linux)
    # install home-manager, then:
    just framework-rebuild

  NixOS Server
    # generate hardware-configuration.nix
    just server-gen-hardware
    # review + commit hardware config, then:
    just server-rebuild

Run `just` from ~/dotfiles to see all available recipes.
EOF
