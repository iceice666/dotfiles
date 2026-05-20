# Dotfiles management recipes

set shell := ["bash", "-euo", "pipefail", "-c"]

repo_root := justfile_directory()
m3air_flake := ".#iceice666@m3air"
framework_flake := ".#framework"
framework_build_attr := ".#nixosConfigurations.framework.config.system.build.toplevel"
themegen_flags := "--scheme tonal-spot --base16-contrast 0.3 --base16-mode follow-palette"

# Apply the M3 Air nix-darwin configuration
[group('host')]
[macos]
switch: theme
    sudo darwin-rebuild switch --flake {{ m3air_flake }} --override-input themegen-cache path:{{ repo_root }}/.cache/themegen/m3air

# Apply the Framework NixOS configuration
[group('host')]
[linux]
switch: theme
    test -e /etc/NIXOS || { echo "Framework switch requires NixOS. The legacy standalone Home Manager path was removed." >&2; exit 1; }
    sudo nixos-rebuild switch --flake {{ framework_flake }} --override-input themegen-cache path:{{ repo_root }}/.cache/themegen/framework

# Dry-build the M3 Air nix-darwin configuration
[group('host')]
[macos]
build: theme
    darwin-rebuild build --flake {{ m3air_flake }} --override-input themegen-cache path:{{ repo_root }}/.cache/themegen/m3air

# Dry-build the Framework NixOS configuration
[group('host')]
[linux]
build: theme
    nix build {{ framework_build_attr }} --override-input themegen-cache path:{{ repo_root }}/.cache/themegen/framework

# Set the Framework NixOS configuration for next boot
[group('host')]
[linux]
boot: theme
    test -e /etc/NIXOS || { echo "Framework boot activation requires NixOS." >&2; exit 1; }
    sudo nixos-rebuild boot --flake {{ framework_flake }} --override-input themegen-cache path:{{ repo_root }}/.cache/themegen/framework

# Install Homebrew on M3 Air
[group('host')]
[macos]
m3air-homebrew:
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Re-apply macOS system settings without a rebuild
[group('host')]
[macos]
m3air-activate:
    /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u

# Generate concrete theme files for M3 Air
[group('theme')]
[macos]
theme:
    #!/usr/bin/env bash
    set -euo pipefail

    host=m3air
    image='{{ repo_root }}/assets/win_chan.jpg'

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
            printf 'themegen-cache-v2\n'
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
    elif command -v cargo >/dev/null 2>&1; then
        themegen_cmd=(cargo run --manifest-path '{{ repo_root }}/pkgs/themegen/Cargo.toml' --)
    else
        themegen_cmd=(themegen)
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

    render_templates=()
    render_outputs=()

    add_render_scope() {
        local scope=$1
        local template_dir='{{ repo_root }}/themegen/'"$scope"

        [[ -d "$template_dir" ]] || return 0

        while IFS= read -r template; do
            local relative=''${template#"$template_dir"/}
            local output="$tmp_dir/$relative"
            local replaced=0

            for index in "${!render_outputs[@]}"; do
                if [[ "${render_outputs[$index]}" == "$output" ]]; then
                    render_templates[$index]="$template"
                    replaced=1
                    break
                fi
            done

            if [[ "$replaced" == 0 ]]; then
                render_templates+=("$template")
                render_outputs+=("$output")
            fi
        done < <(find "$template_dir" -type f | sort)
    }

    add_render_scope common
    add_render_scope "$host"

    render_args=()
    for index in "${!render_templates[@]}"; do
        render_args+=(--render "${render_templates[$index]}=${render_outputs[$index]}")
    done

    "${themegen_cmd[@]}" render \
        --image "$image" \
        {{ themegen_flags }} \
        "${render_args[@]}"

    if [[ -d "$cache_dir" ]]; then
        chmod -R u+w "$cache_dir"
    fi
    rm -rf "$cache_dir"
    mv "$tmp_dir" "$cache_dir"
    tmp_dir=''

    chmod -R u+w "$cache_dir"
    printf '%s\n' "$input_fingerprint" > "$fingerprint_file"
    echo "themegen cache regenerated for $host"

# Generate concrete theme files for Framework
[group('theme')]
[linux]
theme:
    #!/usr/bin/env bash
    set -euo pipefail

    host=framework
    image='{{ repo_root }}/assets/mzen.png'

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
            printf 'themegen-cache-v2\n'
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
    elif command -v cargo >/dev/null 2>&1; then
        themegen_cmd=(cargo run --manifest-path '{{ repo_root }}/pkgs/themegen/Cargo.toml' --)
    else
        themegen_cmd=(themegen)
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

    render_templates=()
    render_outputs=()

    add_render_scope() {
        local scope=$1
        local template_dir='{{ repo_root }}/themegen/'"$scope"

        [[ -d "$template_dir" ]] || return 0

        while IFS= read -r template; do
            local relative=''${template#"$template_dir"/}
            local output="$tmp_dir/$relative"
            local replaced=0

            for index in "${!render_outputs[@]}"; do
                if [[ "${render_outputs[$index]}" == "$output" ]]; then
                    render_templates[$index]="$template"
                    replaced=1
                    break
                fi
            done

            if [[ "$replaced" == 0 ]]; then
                render_templates+=("$template")
                render_outputs+=("$output")
            fi
        done < <(find "$template_dir" -type f | sort)
    }

    add_render_scope common
    add_render_scope "$host"

    render_args=()
    for index in "${!render_templates[@]}"; do
        render_args+=(--render "${render_templates[$index]}=${render_outputs[$index]}")
    done

    "${themegen_cmd[@]}" render \
        --image "$image" \
        {{ themegen_flags }} \
        "${render_args[@]}"

    if [[ -d "$cache_dir" ]]; then
        chmod -R u+w "$cache_dir"
    fi
    rm -rf "$cache_dir"
    mv "$tmp_dir" "$cache_dir"
    tmp_dir=''

    chmod -R u+w "$cache_dir"
    printf '%s\n' "$input_fingerprint" > "$fingerprint_file"
    echo "themegen cache regenerated for $host"

# Render an HTML preview for the current or specified wallpaper palette
[group('theme')]
[macos]
theme-preview image='':
    #!/usr/bin/env bash
    set -euo pipefail

    image='{{ image }}'

    if [[ -z "$image" ]]; then
        image='{{ repo_root }}/assets/win_chan.jpg'
    fi

    if [[ ! -f "$image" ]]; then
        echo "Wallpaper not found: $image" >&2
        exit 1
    fi

    if [[ -n "${THEMEGEN_BIN:-}" ]]; then
        themegen_cmd=("$THEMEGEN_BIN")
    elif command -v cargo >/dev/null 2>&1; then
        themegen_cmd=(cargo run --manifest-path '{{ repo_root }}/pkgs/themegen/Cargo.toml' --)
    else
        themegen_cmd=(themegen)
    fi

    output='{{ repo_root }}/.cache/themegen/preview/index.html'
    mkdir -p "$(dirname "$output")"

    "${themegen_cmd[@]}" render \
        --image "$image" \
        {{ themegen_flags }} \
        --render '{{ repo_root }}/themegen/preview.html='"$output"

    echo "themegen preview rendered to $output"

    if command -v open >/dev/null 2>&1; then
        open "$output"
    elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$output"
    fi

# Render an HTML preview for the current or specified wallpaper palette
[group('theme')]
[linux]
theme-preview image='':
    #!/usr/bin/env bash
    set -euo pipefail

    image='{{ image }}'

    if [[ -z "$image" ]]; then
        image='{{ repo_root }}/assets/mzen.png'
    fi

    if [[ ! -f "$image" ]]; then
        echo "Wallpaper not found: $image" >&2
        exit 1
    fi

    if [[ -n "${THEMEGEN_BIN:-}" ]]; then
        themegen_cmd=("$THEMEGEN_BIN")
    elif command -v cargo >/dev/null 2>&1; then
        themegen_cmd=(cargo run --manifest-path '{{ repo_root }}/pkgs/themegen/Cargo.toml' --)
    else
        themegen_cmd=(themegen)
    fi

    output='{{ repo_root }}/.cache/themegen/preview/index.html'
    mkdir -p "$(dirname "$output")"

    "${themegen_cmd[@]}" render \
        --image "$image" \
        {{ themegen_flags }} \
        --render '{{ repo_root }}/themegen/preview.html='"$output"

    echo "themegen preview rendered to $output"

    if command -v open >/dev/null 2>&1; then
        open "$output"
    elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$output"
    fi

# Update all flake inputs, or selected inputs when names are passed
[group('flake')]
update *inputs:
    nix flake update {{ inputs }}

# Check formatting, Justfile metadata, and flake outputs
[group('flake')]
check: fmt-check _just-check
    nix flake check --all-systems

# Format all files via treefmt-nix
[group('flake')]
fmt:
    nix fmt

# Check Justfile formatting without modifying files
[group('flake')]
fmt-check:
    just --unstable --fmt --check

_just-check:
    just --summary >/dev/null
    just --groups --unsorted >/dev/null
    just --list --unsorted >/dev/null
    just --dump --dump-format json >/dev/null

# Encrypt a secret file in place, or from a plaintext source file
[group('secrets')]
secret-encrypt secret plaintext='':
    #!/usr/bin/env bash
    set -euo pipefail

    secret='{{ secret }}'
    plaintext='{{ plaintext }}'

    SOPS_AGE_KEY_FILE="$(just --quiet _sops-age-key-file "$secret")"
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
[group('secrets')]
secret-decrypt secret output='':
    #!/usr/bin/env bash
    set -euo pipefail

    secret='{{ secret }}'
    output='{{ output }}'

    SOPS_AGE_KEY_FILE="$(just --quiet _sops-age-key-file "$secret")"
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
[group('secrets')]
secret-edit secret:
    #!/usr/bin/env bash
    set -euo pipefail

    secret='{{ secret }}'

    SOPS_AGE_KEY_FILE="$(just --quiet _sops-age-key-file "$secret")"
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

_sops-age-key-file secret:
    #!/usr/bin/env bash
    set -euo pipefail

    secret='{{ secret }}'

    if [[ -n "${SOPS_AGE_KEY_FILE:-}" ]]; then
        printf '%s\n' "$SOPS_AGE_KEY_FILE"
        exit 0
    fi

    if [[ "$secret" == sensitive/shared/* ]]; then
        candidates=(
            "$HOME/.config/sops/age/keys.txt"
            "$HOME/Library/Application Support/sops/age/keys.txt"
            /var/lib/sops-nix/key.txt
        )
    else
        candidates=(
            /var/lib/sops-nix/key.txt
            "$HOME/.config/sops/age/keys.txt"
            "$HOME/Library/Application Support/sops/age/keys.txt"
        )
    fi

    for candidate in "${candidates[@]}"; do
        if [[ -f "$candidate" ]]; then
            printf '%s\n' "$candidate"
            exit 0
        fi
    done

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
    exit 1

# Search nixpkgs for a package across platforms
[group('nix')]
search query:
    #!/usr/bin/env bash
    set -euo pipefail

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

# Remove old generations and collect garbage
[confirm]
[group('nix')]
gc:
    sudo nix-collect-garbage -d

# Show disk usage of the Nix store
[group('nix')]
store-size:
    du -sh /nix/store
