# Dotfiles management recipes

set shell := ["bash", "-euo", "pipefail", "-c"]

repo_root := justfile_directory()
host := if os() == "macos" { "m3air" } else { "framework" }
m3air_flake := ".#m3air"
framework_kaguya_cache := repo_root / ".cache/kaguya/framework"
framework_system := ".#nixosConfigurations.framework.config.system.build.toplevel"
gce_dns_system := ".#nixosConfigurations.gce-dns.config.system.build.toplevel"
gce_dns_image := ".#nixosConfigurations.gce-dns.config.system.build.googleComputeImage"
scripts := repo_root / "scripts"

# Apply the M3 Air nix-darwin configuration
[group('host')]
[macos]
switch:
    sudo darwin-rebuild switch --flake {{ m3air_flake }}

# Apply the Framework NixOS configuration
[group('host')]
[linux]
switch: _kaguya-cache
    nix build {{ framework_system }} --override-input kaguya-cache path:{{ framework_kaguya_cache }}
    sudo ./result/bin/switch-to-configuration switch

# Apply the local host plus all remote host configurations
[group('host')]
switch-all: switch homolab-switch gateway-switch gce-dns-switch lumo-switch

# Dry-build the M3 Air nix-darwin configuration
[group('host')]
[macos]
build:
    darwin-rebuild build --flake {{ m3air_flake }}

# Dry-build the Framework NixOS configuration
[group('host')]
[linux]
build: _kaguya-cache
    nix build {{ framework_system }} --override-input kaguya-cache path:{{ framework_kaguya_cache }}

# Set the Framework NixOS configuration for next boot
[group('host')]
[linux]
boot: _kaguya-cache
    test -e /etc/NIXOS || { echo "Framework boot activation requires NixOS." >&2; exit 1; }
    nix build {{ framework_system }} --override-input kaguya-cache path:{{ framework_kaguya_cache }}
    sudo ./result/bin/switch-to-configuration boot

# Ensure the local Kaguya Nix path input cache exists before Framework builds
[linux]
_kaguya-cache:
    {{ scripts }}/kaguya-cache ensure

# Refresh the Kaguya browser build from homolab into the local Nix path input cache
[group('host')]
[linux]
kaguya:
    {{ scripts }}/kaguya-cache refresh

# Incrementally sync the Kaguya cache (faster updates)
[group('host')]
[linux]
kaguya-sync:
    {{ scripts }}/kaguya-cache sync

# Wake homolab via Wake-on-LAN and wait for the LLM endpoint to be ready
[group('host')]
homolab-wake:
    {{ scripts }}/homolab-wake

# Suspend homolab immediately (return to off state)
[group('host')]
homolab-sleep:
    ssh iceice666@homolab systemctl suspend

# Apply the homolab NixOS configuration over SSH
[group('host')]
homolab-switch:
    HOMOLAB_WAKE_MODE=ssh {{ scripts }}/homolab-wake
    nix develop --command deploy .#homolab --skip-checks

# Stage the homolab NixOS configuration for next boot over SSH
[group('host')]
homolab-boot:
    HOMOLAB_WAKE_MODE=ssh {{ scripts }}/homolab-wake
    nix develop --command deploy .#homolab --boot --skip-checks

# Dry-build the homolab NixOS configuration on the server
[group('host')]
homolab-build:
    HOMOLAB_WAKE_MODE=ssh {{ scripts }}/homolab-wake
    nix develop --command deploy .#homolab --dry-activate --skip-checks

# Refresh hardware-configuration.nix from the live homolab server
[group('host')]
homolab-gen-hardware:
    HOMOLAB_WAKE_MODE=ssh {{ scripts }}/homolab-wake
    ssh iceice666@homolab sudo nixos-generate-config --show-hardware-config \
        > {{ repo_root }}/hosts/homolab/configuration/hardware-configuration.nix

# Smoke-check the homolab OpenAI-compatible LLM endpoint
[group('host')]
homolab-llama-smoke:
    {{ scripts }}/homolab-wake
    LLAMA_SWAP_BASE_URL="${LLAMA_SWAP_BASE_URL:-http://homolab:11434}" \
        {{ scripts }}/llama-swap-smoke

# Build the gce-dns NixOS system toplevel
[group('host')]
gce-dns-build:
    nix build {{ gce_dns_system }}

# Build the gce-dns Google Compute Engine image
[group('host')]
gce-dns-image:
    nix build {{ gce_dns_image }}

# Bootstrap an official Alpine 3.24 installation for gateway
[group('host')]
gateway-bootstrap target='gateway':
    {{ scripts }}/alpine-bootstrap gateway {{ target }}

# Dry-activate the gateway root Home Manager profile
[group('host')]
gateway-build:
    nix develop --command deploy .#gateway --dry-activate --skip-checks

# Apply the gateway root Home Manager profile
[group('host')]
gateway-switch:
    nix develop --command deploy .#gateway --skip-checks

# Apply the gce-dns NixOS configuration over Tailscale SSH
[group('host')]
gce-dns-switch:
    nix develop --command deploy .#gce-dns --skip-checks

# Bootstrap the existing Alpine 3.24 installation for lumo
[group('host')]
lumo-bootstrap target='lumo':
    {{ scripts }}/alpine-bootstrap lumo {{ target }}

# Dry-activate the lumo root Home Manager profile
[group('host')]
lumo-build:
    nix develop --command deploy .#lumo --dry-activate --skip-checks

# Apply the lumo root Home Manager profile
[group('host')]
lumo-switch:
    nix develop --command deploy .#lumo --skip-checks

# Smoke-check lumo services after deployment
[group('host')]
lumo-smoke target='lumo':
    {{ scripts }}/lumo-smoke {{ target }}

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

# Generate a local concrete theme cache for the current host
[group('theme')]
theme:
    #!/usr/bin/env bash
    set -euo pipefail
    wallpaper=$(find '{{ repo_root }}/hosts/{{ host }}' -maxdepth 1 -name 'wallpaper.*' | head -1)
    '{{ scripts }}/themegen-cache' generate '{{ host }}' "$wallpaper"

# Render an HTML preview for the current or specified wallpaper palette
[group('theme')]
theme-preview image='':
    #!/usr/bin/env bash
    set -euo pipefail
    image='{{ image }}'
    if [[ -z "$image" ]]; then
        image=$(find '{{ repo_root }}/hosts/{{ host }}' -maxdepth 1 -name 'wallpaper.*' | head -1)
    fi
    '{{ scripts }}/themegen-cache' preview '{{ host }}' "$image"

# Update all flake inputs, or selected inputs when names are passed
[group('flake')]
update *inputs:
    nix flake update {{ inputs }}

# Ask a coding agent to update custom package versions and commit the result
[group('flake')]
update-custom-pkgs agent='codex':
    {{ scripts }}/update-custom-pkgs-agent '{{ agent }}' '{{ repo_root }}'

# Update custom binary packages to their latest GitHub releases
[group('flake')]
update-pkgs *args:
    {{ scripts }}/update-pkgs {{ args }}

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
    {{ scripts }}/sops-secret encrypt '{{ secret }}' '{{ plaintext }}'

# Decrypt a secret file to stdout (text) or an output file
[group('secrets')]
secret-decrypt secret output='':
    {{ scripts }}/sops-secret decrypt '{{ secret }}' '{{ output }}'

# Edit a secret safely in place with sops
[group('secrets')]
secret-edit secret:
    {{ scripts }}/sops-secret edit '{{ secret }}'

# Re-encrypt secrets under the given path (default: sensitive/) so their recipients match .sops.yaml
[group('secrets')]
secret-refresh path='sensitive':
    #!/usr/bin/env bash
    set -euo pipefail

    target='{{ path }}'

    if [[ -f "$target" ]]; then
        files=("$target")
    elif [[ -d "$target" ]]; then
        mapfile -t files < <(find "$target" -type f \( \
            -name '*.yaml' -o -name '*.yml' -o -name '*.json' \
            -o -name '*.env'  -o -name '*.ini' \
            -o -name '*.key'  -o -name '*.pem' \
        \) | sort)
    else
        echo "secret-refresh: not a file or directory: $target" >&2
        exit 1
    fi

    if (( ${#files[@]} == 0 )); then
        echo "secret-refresh: no candidate secret files under $target" >&2
        exit 0
    fi

    failed=0
    for file in "${files[@]}"; do
        echo ">>> $file"
        if ! sops updatekeys --yes "$file"; then
            echo "!!! failed: $file" >&2
            failed=1
        fi
    done

    exit "$failed"

# Search nixpkgs for a package across platforms
[group('nix')]
search query:
    {{ scripts }}/nix-search-platforms '{{ query }}'

# Remove old generations and collect garbage
[confirm]
[group('nix')]
gc:
    sudo nix-collect-garbage -d

# Show disk usage of the Nix store
[group('nix')]
store-size:
    du -sh /nix/store
