# Dotfiles management recipes

# Show available recipes
default:
    @just --choose --unsorted

# ── M3 Air (macOS, nix-darwin) ───────────────────────────────────────────────

# Rebuild M3Air system
m3air-rebuild:
    sudo darwin-rebuild switch --flake .#iceice666@m3air

# Install Homebrew (first-time setup)
m3air-homebrew:
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Apply macOS system settings immediately (without rebuild)
m3air-activate:
    /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u

# ── Framework (Void Linux, home-manager) ─────────────────────────────────────

# Rebuild Framework home environment
framework-rebuild:
    home-manager switch --flake .#iceice666@framework

# ── NixOS Server ─────────────────────────────────────────────────────────────

# Rebuild NixOS server
server-rebuild:
    sudo nixos-rebuild switch --flake .#homolab

# Generate hardware config on the server (run on the server itself)
server-gen-hardware:
    sudo nixos-generate-config --show-hardware-config > hosts/server/configuration/hardware-configuration.nix

# ── Flake maintenance ─────────────────────────────────────────────────────────

# Update all flake inputs
update:
    nix flake update

# Update a single flake input (e.g. just update-input nixpkgs)
update-input input:
    nix flake update {{ input }}

# Check flake outputs for errors
check:
    nix flake check

# Format all Nix files
fmt:
    nixfmt .

# ── Nixpkgs search ───────────────────────────────────────────────────────────

# Search nixpkgs for a package across platforms (filters by actual platform support)
search query:
    #!/usr/bin/env bash
    NIX="nix --extra-experimental-features 'nix-command flakes'"

    pkg_supported() {
        local system=$1 pkg=$2
        local result
        result=$(nix eval --json \
            --extra-experimental-features 'nix-command flakes' \
            "nixpkgs#legacyPackages.$system.$pkg.meta.available" 2>/dev/null) || return 1
        [[ "$result" == "true" ]]
    }

    search_system() {
        local system=$1 query=$2 found=false
        echo "=== $system ==="
        while IFS= read -r line; do
            # strip ANSI escape codes, then extract pkg name from "* legacyPackages.SYSTEM.pkgname (ver)"
            local clean pkg
            clean=$(echo "$line" | sed 's/\x1b\[[0-9;]*m//g')
            pkg=$(echo "$clean" | rg -o 'legacyPackages\.[^.]+\.(\S+) ' -r '$1')
            [[ -z "$pkg" ]] && continue
            pkg_supported "$system" "$pkg" || continue
            echo "$clean"
            found=true
        done < <(nix search --extra-experimental-features 'nix-command flakes' \
            "nixpkgs#legacyPackages.$system" "$query" 2>/dev/null || true)
        [[ "$found" == "false" ]] && echo "(no results for $system)"
        echo ""
    }

    for system in aarch64-darwin x86_64-linux; do
        search_system "$system" "{{ query }}"
    done

# ── Garbage collection ────────────────────────────────────────────────────────

# Remove old generations and collect garbage
gc:
    sudo nix-collect-garbage -d

# Show disk usage of the Nix store
store-size:
    du -sh /nix/store
