# Dotfiles management recipes

set shell := ["bash", "-euo", "pipefail", "-c"]

repo_root := justfile_directory()
m3air_target := ".#iceice666@m3air"
framework_target := ".#iceice666@framework"
home_manager := "nix run github:nix-community/home-manager/release-25.11 --"

# Apply the current machine configuration
switch: && post-switch
    #!/usr/bin/env bash
    host=$(uname -n | tr '[:upper:]' '[:lower:]')
    just themegen-generate "$host"
    just _switch "$host"

# Run host-specific lifecycle tasks after switching
post-switch:
    #!/usr/bin/env bash
    host=$(uname -n | tr '[:upper:]' '[:lower:]')
    just _post-switch "$host"

# Dry-build the current machine configuration
build:
    #!/usr/bin/env bash
    host=$(uname -n | tr '[:upper:]' '[:lower:]')
    just themegen-generate "$host"
    just _build "$host"

boot:
    #!/usr/bin/env bash
    host=$(uname -n | tr '[:upper:]' '[:lower:]')
    just themegen-generate "$host"
    just _boot "$host"

_switch host:
    #!/usr/bin/env bash
    host='{{ host }}'

    case "$host" in
    m3air)
        sudo darwin-rebuild switch --flake {{ m3air_target }} --override-input themegen-cache path:{{ repo_root }}/.cache/themegen/m3air
        ;;
    framework)
        if [[ -e /etc/NIXOS ]]; then
            sudo nixos-rebuild switch --flake .#framework --override-input themegen-cache path:{{ repo_root }}/.cache/themegen/framework
        else
            just ensure-nix-daemon
            {{ home_manager }} switch --flake {{ framework_target }} --override-input themegen-cache path:{{ repo_root }}/.cache/themegen/framework
        fi
        ;;
        *)
            just _unknown-host "$host" rebuild
            ;;
    esac

_build host:
    #!/usr/bin/env bash
    host='{{ host }}'

    case "$host" in
    m3air)
        sudo darwin-rebuild build --flake {{ m3air_target }} --override-input themegen-cache path:{{ repo_root }}/.cache/themegen/m3air
        ;;
    framework)
        if [[ -e /etc/NIXOS ]]; then
            nix build .#nixosConfigurations.framework.config.system.build.toplevel --override-input themegen-cache path:{{ repo_root }}/.cache/themegen/framework
        else
            just ensure-nix-daemon
            {{ home_manager }} build --flake {{ framework_target }} --override-input themegen-cache path:{{ repo_root }}/.cache/themegen/framework
        fi
        ;;
        *)
            just _unknown-host "$host" build
            ;;
    esac

_boot host:
    #!/usr/bin/env bash
    host='{{ host }}'

    case "$host" in
    m3air)
        just _unknown-host "$host" boot
        ;;
    framework)
        if [[ -e /etc/NIXOS ]]; then
            sudo nixos-rebuild boot --flake .#framework --override-input themegen-cache path:{{ repo_root }}/.cache/themegen/framework
        else
            just _unknown-host "$host" boot
        fi
        ;;
    *)
        just _unknown-host "$host" boot
        ;;
    esac

_post-switch host:
    #!/usr/bin/env bash
    host='{{ host }}'

    case "$host" in
    m3air)
        ;;
    framework)
        if [[ ! -e /etc/NIXOS && -x "$HOME/.nix-profile/bin/framework-post-switch" ]]; then
            "$HOME/.nix-profile/bin/framework-post-switch"
        fi
        ;;
        *)
            just _unknown-host "$host" post-switch
            ;;
    esac

_unknown-host host action:
    #!/usr/bin/env bash
    host='{{ host }}'
    action='{{ action }}'
    os=$(uname -s)

    case "$action" in
        build)
            hint="Use an explicit host build recipe or add a host mapping."
            ;;
        rebuild)
            hint="Use an explicit host rebuild recipe or add a host mapping."
            ;;
        post-switch)
            hint="Add a post-switch mapping if needed."
            ;;
        *)
            hint="Use an explicit host recipe or add a host mapping."
            ;;
    esac

    if [[ "$os" == "Darwin" ]]; then
        echo "Unknown Darwin host '$host'. $hint" >&2
    else
        echo "Unknown host '$host'. $hint" >&2
    fi
    exit 1

# ── M3 Air (macOS, nix-darwin) ───────────────────────────────────────────────

# Rebuild M3Air system
m3air-rebuild: (themegen-generate "m3air")
    just _switch m3air

# Dry-build M3Air system
m3air-build: (themegen-generate "m3air")
    just _build m3air

# Install Homebrew (first-time setup)
m3air-homebrew:
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Apply macOS system settings immediately (without rebuild)
m3air-activate:
    /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u

# ── Framework (NixOS, with legacy Arch/Home Manager fallback) ────────────────

# Ensure the Lix daemon socket is loaded and active for legacy non-NixOS use
ensure-nix-daemon:
    #!/usr/bin/env bash
    if [[ "$(uname -s)" != "Linux" ]]; then
        exit 0
    fi

    if systemctl is-active --quiet nix-daemon.socket; then
        exit 0
    fi

    sudo -v

    if ! systemctl cat nix-daemon.socket >/dev/null 2>&1; then
        if [[ ! -e /etc/systemd/system/nix-daemon.socket ]]; then
            echo "nix-daemon.socket not found; install Lix before running Nix recipes." >&2
            exit 1
        fi

        sudo systemctl daemon-reload
    fi

    sudo systemctl enable --now nix-daemon.socket

# Install legacy Arch-owned dependencies and services for the Framework host
framework-bootstrap:
    #!/usr/bin/env bash
    if [[ "$(uname -s)" != "Linux" ]]; then
        echo "This bootstrap is only for the Framework Arch Linux host." >&2
        exit 1
    fi

    if ! command -v pacman >/dev/null 2>&1; then
        echo "pacman not found; this bootstrap expects Arch Linux." >&2
        exit 1
    fi

    if ! systemctl cat nix-daemon.socket >/dev/null 2>&1; then
        echo "nix-daemon.socket not found; install Lix before running this bootstrap." >&2
        exit 1
    fi

    packages=(
        accountsservice
        bluez
        bluez-utils
        cage
        dbus
        fprintd
        greetd
        greetd-regreet
        mesa
        networkmanager
        pipewire
        pipewire-pulse
        polkit
        wireplumber
        xdg-desktop-portal
        xdg-desktop-portal-gnome
        xdg-desktop-portal-gtk
    )

    sudo -v
    sudo systemctl daemon-reload
    sudo systemctl enable --now nix-daemon.socket
    sudo pacman -S --needed "${packages[@]}"
    sudo systemctl daemon-reload
    sudo systemctl enable --now NetworkManager.service bluetooth.service
    sudo systemctl start fprintd.service
    sudo systemctl enable greetd.service

    if systemctl --user show-environment >/dev/null 2>&1; then
        systemctl --user enable --now pipewire.service pipewire-pulse.service wireplumber.service
    else
        printf '%s\n' \
            "User systemd is not available in this shell." \
            "After logging into a normal user session, run:" \
            "  systemctl --user enable --now pipewire.service pipewire-pulse.service wireplumber.service" >&2
    fi

# Rebuild Framework system
framework-rebuild: (themegen-generate "framework") && framework-post-switch
    just _switch framework

# Dry-build Framework system
framework-build: (themegen-generate "framework")
    just _build framework

# Boot Framework system for next reboot
framework-boot: (themegen-generate "framework")
    just _boot framework

# Re-apply legacy Arch-owned GUI integration after a Framework Home Manager switch
framework-post-switch:
    just _post-switch framework

# ── Flake maintenance ─────────────────────────────────────────────────────────

# Update all flake inputs
update: ensure-nix-daemon
    nix flake update

# Update a single flake input (e.g. just update-input nixpkgs)
update-input input: ensure-nix-daemon
    nix flake update {{ input }}

# Check flake outputs for errors
check: ensure-nix-daemon
    nix flake check --all-systems

# Format all files via treefmt-nix
fmt: ensure-nix-daemon
    nix fmt

# Generate concrete theme files for a host before building
themegen-generate host:
    #!/usr/bin/env bash
    host='{{ host }}'

    case "$host" in
        m3air)
            image='{{ repo_root }}/assets/win_chan.jpg'
            ;;
        framework)
            image='{{ repo_root }}/assets/mzen.png'
            ;;
        *)
            just _unknown-host "$host" themegen-generate
            ;;
    esac

    if [[ ! -f "$image" ]]; then
        echo "Wallpaper not found: $image" >&2
        exit 1
    fi

    cache_dir='{{ repo_root }}/.cache/themegen/'"$host"
    state_dir='{{ repo_root }}/.cache/themegen/.state'
    fingerprint_file="$state_dir/$host.sha256"

    hash_file() {
        local file=$1

        if command -v sha256sum >/dev/null 2>&1; then
            sha256sum "$file" | awk '{print $1}'
        else
            shasum -a 256 "$file" | awk '{print $1}'
        fi
    }

    hash_stdin() {
        if command -v sha256sum >/dev/null 2>&1; then
            sha256sum | awk '{print $1}'
        else
            shasum -a 256 | awk '{print $1}'
        fi
    }

    fingerprint_inputs() {
        {
            printf 'themegen-cache-v1\n'
            printf 'host %s\n' "$host"
            printf 'render-options scheme=tonal-spot base16-contrast=0.3 base16-mode=follow-palette\n'
            printf 'image %s %s\n' "$image" "$(hash_file "$image")"

            for scope in common "$host"; do
                local template_dir='{{ repo_root }}/themegen/'"$scope"
                [[ -d "$template_dir" ]] || continue

                while IFS= read -r template; do
                    local relative=''${template#"$template_dir"/}
                    printf 'template %s %s %s\n' "$scope" "$relative" "$(hash_file "$template")"
                done < <(find "$template_dir" -type f | sort)
            done
        } | hash_stdin
    }

    input_fingerprint=$(fingerprint_inputs)

    cache_has_files() {
        [[ -d "$cache_dir" ]] || return 1
        [[ -n "$(find "$cache_dir" -type f -print -quit)" ]]
    }

    if [[ -f "$fingerprint_file" && "$(cat "$fingerprint_file")" == "$input_fingerprint" ]] && cache_has_files; then
        echo "themegen cache up to date for $host"
        exit 0
    fi

    if [[ -n "${THEMEGEN_BIN:-}" ]]; then
        themegen_cmd=("$THEMEGEN_BIN")
    elif command -v themegen >/dev/null 2>&1; then
        themegen_cmd=(themegen)
    else
        themegen_cmd=(cargo run --manifest-path '{{ repo_root }}/pkgs/themegen/Cargo.toml' --)
    fi

    mkdir -p '{{ repo_root }}/.cache/themegen' "$state_dir"
    tmp_dir=$(mktemp -d '{{ repo_root }}/.cache/themegen/.tmp-'"$host"'.XXXXXXXXXX')

    cleanup_tmp() {
        if [[ -d "$tmp_dir" ]]; then
            chmod -R u+w "$tmp_dir"
            rm -rf "$tmp_dir"
        fi
    }

    trap cleanup_tmp EXIT

    render_scope() {
        local scope=$1
        local template_dir='{{ repo_root }}/themegen/'"$scope"

        [[ -d "$template_dir" ]] || return 0

        while IFS= read -r template; do
            local relative=''${template#"$template_dir"/}
            "${themegen_cmd[@]}" render \
                --image "$image" \
                --scheme tonal-spot \
                --base16-contrast 0.3 \
                --base16-mode follow-palette \
                --render "$template=$tmp_dir/$relative"
        done < <(find "$template_dir" -type f | sort)
    }

    render_scope common
    render_scope "$host"

    if [[ -d "$cache_dir" ]]; then
        chmod -R u+w "$cache_dir"
    fi
    rm -rf "$cache_dir"
    mv "$tmp_dir" "$cache_dir"
    tmp_dir=''

    chmod -R u+w "$cache_dir"
    printf '%s\n' "$input_fingerprint" > "$fingerprint_file"
    echo "themegen cache regenerated for $host"

# Preview the current or specified wallpaper palette
themegen-preview image='':
    #!/usr/bin/env bash
    image='{{ image }}'

    if [[ -z "$image" ]]; then
        host=$(uname -n | tr '[:upper:]' '[:lower:]')

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
search query: ensure-nix-daemon
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
gc: ensure-nix-daemon
    sudo nix-collect-garbage -d

# Show disk usage of the Nix store
store-size:
    du -sh /nix/store
