# Dotfiles management recipes

set shell := ["bash", "-euo", "pipefail", "-c"]

m3air_target := ".#iceice666@m3air"
framework_target := ".#iceice666@framework"
server_target := ".#homolab"

# Show available recipes
default:
    @just --choose --unsorted

# Dry-build the current machine configuration
build:
    #!/usr/bin/env bash
    host=$(hostname | tr '[:upper:]' '[:lower:]')
    os=$(uname -s)

    case "$host" in
        m3air)
            sudo darwin-rebuild build --flake {{ m3air_target }}
            ;;
        framework)
            home-manager build --flake {{ framework_target }}
            ;;
        homolab|server)
            sudo nixos-rebuild build --flake {{ server_target }}
            ;;
        *)
            if [[ "$os" == "Darwin" ]]; then
                echo "Unknown Darwin host '$host'. Use 'just m3air-rebuild' or add a host mapping." >&2
            else
                echo "Unknown host '$host'. Use an explicit host recipe or add a host mapping." >&2
            fi
            exit 1
            ;;
    esac

# Apply the current machine configuration
switch:
    #!/usr/bin/env bash
    host=$(hostname | tr '[:upper:]' '[:lower:]')
    os=$(uname -s)

    case "$host" in
        m3air)
            sudo darwin-rebuild switch --flake {{ m3air_target }}
            ;;
        framework)
            home-manager switch --flake {{ framework_target }}
            ;;
        homolab|server)
            sudo nixos-rebuild switch --flake {{ server_target }}
            ;;
        *)
            if [[ "$os" == "Darwin" ]]; then
                echo "Unknown Darwin host '$host'. Use 'just m3air-rebuild' or add a host mapping." >&2
            else
                echo "Unknown host '$host'. Use an explicit host recipe or add a host mapping." >&2
            fi
            exit 1
            ;;
    esac

# ── M3 Air (macOS, nix-darwin) ───────────────────────────────────────────────

# Rebuild M3Air system
m3air-rebuild:
    sudo darwin-rebuild switch --flake {{ m3air_target }}

# Dry-build M3Air system
m3air-build:
    sudo darwin-rebuild build --flake {{ m3air_target }}

# Install Homebrew (first-time setup)
m3air-homebrew:
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Apply macOS system settings immediately (without rebuild)
m3air-activate:
    /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u

# ── Framework (Void Linux, home-manager) ─────────────────────────────────────

# Rebuild Framework home environment
framework-rebuild:
    home-manager switch --flake {{ framework_target }}

# Dry-build Framework home environment
framework-build:
    home-manager build --flake {{ framework_target }}

# ── NixOS Server ─────────────────────────────────────────────────────────────

# Rebuild NixOS server
server-rebuild:
    #!/usr/bin/env bash
    host=$(hostname | tr '[:upper:]' '[:lower:]')

    case "$host" in
        homolab|server)
            sudo nixos-rebuild switch --flake {{ server_target }}
            ;;
        *)
            echo "Refusing to run server-rebuild from '$host'. Run this recipe on homolab instead." >&2
            exit 1
            ;;
    esac

# Dry-build NixOS server
server-build:
    #!/usr/bin/env bash
    host=$(hostname | tr '[:upper:]' '[:lower:]')

    case "$host" in
        homolab|server)
            sudo nixos-rebuild build --flake {{ server_target }}
            ;;
        *)
            echo "Refusing to run server-build from '$host'. Run this recipe on homolab instead." >&2
            exit 1
            ;;
    esac

# Generate hardware config on the server (run on the server itself)
server-gen-hardware:
    #!/usr/bin/env bash
    host=$(hostname | tr '[:upper:]' '[:lower:]')
    output=hosts/server/configuration/hardware-configuration.nix
    tmp=$(mktemp)
    trap 'rm -f "$tmp"' EXIT

    case "$host" in
        homolab|server)
            sudo nixos-generate-config --show-hardware-config > "$tmp"
            mv "$tmp" "$output"
            ;;
        *)
            echo "Refusing to overwrite $output from '$host'. Run this recipe on homolab instead." >&2
            exit 1
            ;;
    esac

# ── Flake maintenance ─────────────────────────────────────────────────────────

# Update all flake inputs
update:
    nix flake update

# Update a single flake input (e.g. just update-input nixpkgs)
update-input input:
    nix flake update {{ input }}

# Check flake outputs for errors
check:
    nix flake check --all-systems

# Format all files via treefmt-nix
fmt:
    nix fmt

# ── Secrets ───────────────────────────────────────────────────────────────────

# Encrypt a secret file in place, or from a plaintext source file
secret-encrypt secret plaintext='':
    #!/usr/bin/env bash
    set -euo pipefail
    export SOPS_AGE_KEY_FILE=/var/lib/sops-nix/key.txt

    secret='{{ secret }}'
    plaintext='{{ plaintext }}'

    case "$secret" in
        *.yaml|*.yml|*.json|*.env|*.ini)
            if [[ -n "$plaintext" ]]; then
                sops encrypt --output "$secret" "$plaintext"
            else
                sops encrypt --in-place "$secret"
            fi
            ;;
        *.key|*.pem)
            if [[ -n "$plaintext" ]]; then
                sops encrypt --input-type binary --output-type binary --output "$secret" "$plaintext"
            else
                sops encrypt --input-type binary --output-type binary --in-place "$secret"
            fi
            ;;
        *)
            echo "Unsupported secret file type: $secret" >&2
            exit 1
            ;;
    esac

# Decrypt a secret file to stdout (text) or an output file
secret-decrypt secret output='':
    #!/usr/bin/env bash
    set -euo pipefail
    export SOPS_AGE_KEY_FILE=/var/lib/sops-nix/key.txt

    secret='{{ secret }}'
    output='{{ output }}'

    case "$secret" in
        *.yaml|*.yml|*.json|*.env|*.ini)
            if [[ -n "$output" ]]; then
                sops decrypt --output "$output" "$secret"
            else
                sops decrypt "$secret"
            fi
            ;;
        *.key|*.pem)
            if [[ -z "$output" ]]; then
                echo "Binary secrets require an output path: just secret-decrypt $secret /tmp/output" >&2
                exit 1
            fi
            sops decrypt --input-type binary --output-type binary --output "$output" "$secret"
            ;;
        *)
            echo "Unsupported secret file type: $secret" >&2
            exit 1
            ;;
    esac

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
