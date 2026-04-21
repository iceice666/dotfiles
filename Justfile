# Dotfiles management recipes

set shell := ["bash", "-euo", "pipefail", "-c"]

repo_root := justfile_directory()
m3air_target := ".#iceice666@m3air"
framework_target := ".#iceice666@framework"

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
        *)
            if [[ "$os" == "Darwin" ]]; then
                echo "Unknown Darwin host '$host'. Use 'just m3air-rebuild' or add a host mapping." >&2
            else
                echo "Unknown host '$host'. Use an explicit host recipe or add a host mapping." >&2
            fi
            exit 1
            ;;
    esac

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

# Preview the current or specified wallpaper palette
themegen-preview image='':
    #!/usr/bin/env bash
    image='{{ image }}'

    if [[ -z "$image" ]]; then
        host=$(hostname | tr '[:upper:]' '[:lower:]')

        case "$host" in
            m3air)
                image='{{ repo_root }}/assets/win_chan.jpg'
                ;;
            framework)
                image='{{ repo_root }}/assets/mzen.png'
                ;;
            *)
                echo "Unknown host '$host'. Pass an explicit image: just themegen-preview path/to/image" >&2
                exit 1
                ;;
        esac
    fi

    if [[ ! -f "$image" ]]; then
        echo "Wallpaper not found: $image" >&2
        exit 1
    fi

    themegen palette \
        --image "$image" \
        --scheme tonal-spot \
        --base16-contrast 0.3 \
        --base16-mode follow-palette

# ── Secrets ───────────────────────────────────────────────────────────────────

# Encrypt a secret file in place, or from a plaintext source file
secret-encrypt secret plaintext='':
    #!/usr/bin/env bash
    set -euo pipefail

    secret='{{ secret }}'
    plaintext='{{ plaintext }}'

    resolve_sops_age_key_file() {
        local secret_path=$1

        if [[ -n "${SOPS_AGE_KEY_FILE:-}" ]]; then
            printf '%s\n' "$SOPS_AGE_KEY_FILE"
            return 0
        fi

        local candidate

        if [[ "$secret_path" == sensitive/shared/* ]]; then
            for candidate in \
                "$HOME/.config/sops/age/keys.txt" \
                "$HOME/Library/Application Support/sops/age/keys.txt" \
                /var/lib/sops-nix/key.txt
            do
                if [[ -f "$candidate" ]]; then
                    printf '%s\n' "$candidate"
                    return 0
                fi
            done
        else
            for candidate in \
                /var/lib/sops-nix/key.txt \
                "$HOME/.config/sops/age/keys.txt" \
                "$HOME/Library/Application Support/sops/age/keys.txt"
            do
                if [[ -f "$candidate" ]]; then
                    printf '%s\n' "$candidate"
                    return 0
                fi
            done
        fi

        printf '%s\n' \
            'No age identity file found for sops.' \
            '' \
            'Set SOPS_AGE_KEY_FILE to a valid age identity, or create one in a default location:' \
            '  - /var/lib/sops-nix/key.txt' \
            '  - ~/.config/sops/age/keys.txt' \
            '  - ~/Library/Application Support/sops/age/keys.txt' \
            '' \
            'On m3air, convert your SSH key to an age identity first:' \
            '  mkdir -p "$HOME/Library/Application Support/sops/age"' \
            '  ssh-to-age -private-key -i "$HOME/.ssh/id_ed25519" -o "$HOME/Library/Application Support/sops/age/keys.txt"' >&2
        return 1
    }

    SOPS_AGE_KEY_FILE="$(resolve_sops_age_key_file "$secret")"
    export SOPS_AGE_KEY_FILE

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

    secret='{{ secret }}'
    output='{{ output }}'

    resolve_sops_age_key_file() {
        local secret_path=$1

        if [[ -n "${SOPS_AGE_KEY_FILE:-}" ]]; then
            printf '%s\n' "$SOPS_AGE_KEY_FILE"
            return 0
        fi

        local candidate

        if [[ "$secret_path" == sensitive/shared/* ]]; then
            for candidate in \
                "$HOME/.config/sops/age/keys.txt" \
                "$HOME/Library/Application Support/sops/age/keys.txt" \
                /var/lib/sops-nix/key.txt
            do
                if [[ -f "$candidate" ]]; then
                    printf '%s\n' "$candidate"
                    return 0
                fi
            done
        else
            for candidate in \
                /var/lib/sops-nix/key.txt \
                "$HOME/.config/sops/age/keys.txt" \
                "$HOME/Library/Application Support/sops/age/keys.txt"
            do
                if [[ -f "$candidate" ]]; then
                    printf '%s\n' "$candidate"
                    return 0
                fi
            done
        fi

        printf '%s\n' \
            'No age identity file found for sops.' \
            '' \
            'Set SOPS_AGE_KEY_FILE to a valid age identity, or create one in a default location:' \
            '  - /var/lib/sops-nix/key.txt' \
            '  - ~/.config/sops/age/keys.txt' \
            '  - ~/Library/Application Support/sops/age/keys.txt' \
            '' \
            'On m3air, convert your SSH key to an age identity first:' \
            '  mkdir -p "$HOME/Library/Application Support/sops/age"' \
            '  ssh-to-age -private-key -i "$HOME/.ssh/id_ed25519" -o "$HOME/Library/Application Support/sops/age/keys.txt"' >&2
        return 1
    }

    SOPS_AGE_KEY_FILE="$(resolve_sops_age_key_file "$secret")"
    export SOPS_AGE_KEY_FILE

    if [[ -n "$output" && "$output" == "$secret" ]]; then
        echo "Refusing to decrypt '$secret' over itself. Use a different output path or 'just secret-edit $secret'." >&2
        exit 1
    fi

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

# Edit a secret safely in place with sops
secret-edit secret:
    #!/usr/bin/env bash
    set -euo pipefail

    secret='{{ secret }}'

    resolve_sops_age_key_file() {
        local secret_path=$1

        if [[ -n "${SOPS_AGE_KEY_FILE:-}" ]]; then
            printf '%s\n' "$SOPS_AGE_KEY_FILE"
            return 0
        fi

        local candidate

        if [[ "$secret_path" == sensitive/shared/* ]]; then
            for candidate in \
                "$HOME/.config/sops/age/keys.txt" \
                "$HOME/Library/Application Support/sops/age/keys.txt" \
                /var/lib/sops-nix/key.txt
            do
                if [[ -f "$candidate" ]]; then
                    printf '%s\n' "$candidate"
                    return 0
                fi
            done
        else
            for candidate in \
                /var/lib/sops-nix/key.txt \
                "$HOME/.config/sops/age/keys.txt" \
                "$HOME/Library/Application Support/sops/age/keys.txt"
            do
                if [[ -f "$candidate" ]]; then
                    printf '%s\n' "$candidate"
                    return 0
                fi
            done
        fi

        printf '%s\n' \
            'No age identity file found for sops.' \
            '' \
            'Set SOPS_AGE_KEY_FILE to a valid age identity, or create one in a default location:' \
            '  - /var/lib/sops-nix/key.txt' \
            '  - ~/.config/sops/age/keys.txt' \
            '  - ~/Library/Application Support/sops/age/keys.txt' \
            '' \
            'On m3air, convert your SSH key to an age identity first:' \
            '  mkdir -p "$HOME/Library/Application Support/sops/age"' \
            '  ssh-to-age -private-key -i "$HOME/.ssh/id_ed25519" -o "$HOME/Library/Application Support/sops/age/keys.txt"' >&2
        return 1
    }

    SOPS_AGE_KEY_FILE="$(resolve_sops_age_key_file "$secret")"
    export SOPS_AGE_KEY_FILE
    export EDITOR="${EDITOR:-nvim}"

    case "$secret" in
        *.yaml|*.yml|*.json|*.env|*.ini|*.key|*.pem)
            sops "$secret"
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
