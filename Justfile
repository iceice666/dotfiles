# Dotfiles management recipes

set shell := ["bash", "-euo", "pipefail", "-c"]

repo_root := justfile_directory()
host := if os() == "macos" { "m5pro" } else { `cat /etc/hostname | sed 's/-linux$//'` }
m5pro_flake := ".#m5pro"
system_target := if host == "m5pro" { ".#darwinConfigurations.m5pro.system" } else { ".#nixosConfigurations." + host + ".config.system.build.toplevel" }
scripts := repo_root / "scripts"

# Apply the M5 Pro nix-darwin configuration
[group('host')]
[macos]
switch:
    sudo darwin-rebuild switch --flake {{ m5pro_flake }}

# Apply the current NixOS host configuration
[group('host')]
[linux]
switch:
    nix build {{ system_target }}
    sudo nix-env --profile /nix/var/nix/profiles/system --set "$(readlink -f ./result)"
    sudo ./result/bin/switch-to-configuration switch

# Apply the local host plus all remote host configurations
[group('host')]
switch-all: switch lumo-switch worker-switch

# Dry-build the M5 Pro nix-darwin configuration
[group('host')]
[macos]
build:
    darwin-rebuild build --flake {{ m5pro_flake }}

# Dry-build the current NixOS host configuration
[group('host')]
[linux]
build:
    nix build {{ system_target }}

# Set the current NixOS host configuration for next boot
[group('host')]
[linux]
boot:
    test -e /etc/NIXOS || { echo "Boot activation requires NixOS." >&2; exit 1; }
    nix build {{ system_target }}
    sudo nix-env --profile /nix/var/nix/profiles/system --set "$(readlink -f ./result)"
    sudo ./result/bin/switch-to-configuration boot

# Build the UEFI Framework reinstall ISO (does not install or erase disks)
[group('host')]
[linux]
framework-iso:
    nix build .#nixosConfigurations.framework-installer.config.system.build.isoImage --out-link result-framework-iso

# Run non-destructive Framework installer tests
[group('host')]
framework-install-test:
    bash -n {{ scripts }}/framework-install
    python3 {{ scripts }}/tests/test-framework-install.py

# Suspend homolab immediately (return to off state)
[group('host')]
homolab-sleep:
    ssh iceice666@homolab systemctl suspend

# Apply the homolab NixOS configuration locally (run on homolab)
[group('host')]
homolab-switch:
    nix build .#nixosConfigurations.homolab.config.system.build.toplevel
    sudo nix-env --profile /nix/var/nix/profiles/system --set "$(readlink -f ./result)"
    sudo ./result/bin/switch-to-configuration switch

# Stage the homolab NixOS configuration for next boot (run on homolab)
[group('host')]
homolab-boot:
    nix build .#nixosConfigurations.homolab.config.system.build.toplevel
    sudo nix-env --profile /nix/var/nix/profiles/system --set "$(readlink -f ./result)"
    sudo ./result/bin/switch-to-configuration boot

# Dry-build the homolab NixOS configuration (run on homolab)
[group('host')]
homolab-build:
    nix build .#nixosConfigurations.homolab.config.system.build.toplevel

# Refresh hardware-configuration.nix from the live homolab server
homolab-gen-hardware:
    ssh iceice666@homolab sudo nixos-generate-config --show-hardware-config \
        > {{ repo_root }}/hosts/homolab/configuration/hardware-configuration.nix

# Smoke-check the homolab TEA-ASR 1.1 mini endpoint
homolab-tea-asr-smoke:
    TEA_ASR_BASE_URL="${TEA_ASR_BASE_URL:-http://100.110.95.111:19000}" \
        {{ scripts }}/tea-asr-smoke

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

# Clear CLIProxyAPI cooldowns on lumo after an upstream quota reset
[group('host')]
cliproxyapi-reset-cooldown provider='codex' target='lumo':
    {{ scripts }}/cliproxyapi-reset-cooldown '{{ provider }}' '{{ target }}'

# Bootstrap the existing Alpine 3.24 installation for worker (ex-gateway Pi)
[group('host')]
worker-bootstrap target='worker':
    {{ scripts }}/alpine-bootstrap worker {{ target }}

# Dry-activate the worker root Home Manager profile
[group('host')]
worker-build:
    nix develop --command deploy .#worker --dry-activate --skip-checks

# Apply the worker root Home Manager profile
[group('host')]
worker-switch:
    nix develop --command deploy .#worker --skip-checks

# Install or update the m3air Woodpecker agent and Colima runtime
[group('host')]
m3air-agent-install target='m3air':
    {{ scripts }}/m3air-woodpecker-agent install {{ target }}

# Smoke-check the m3air Woodpecker agent and container runtime
[group('host')]
m3air-agent-smoke target='m3air':
    {{ scripts }}/m3air-woodpecker-agent smoke {{ target }}

# Install Homebrew on M5 Pro
[group('host')]
[macos]
m5pro-homebrew:
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Re-apply macOS system settings without a rebuild
[group('host')]
[macos]
m5pro-activate:
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

# Update custom packages to their latest upstream releases
[group('flake')]
update-pkgs:
    pi /skill:update-pkgs

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

# Build SleepGuard.app (Release) via xcodegen + xcodebuild
[group('apps')]
[macos]
sleepguard-build:
    #!/usr/bin/env bash
    set -euo pipefail
    # Clean env: the repo devShell exports Nix SDK/linker variables that break xcodebuild.
    xcodegen_dir="$(dirname "$(command -v xcodegen)")"
    cd {{ repo_root }}/pkgs/sleepguard
    env -i HOME="$HOME" USER="$USER" PATH="/usr/bin:/bin:/usr/sbin:/sbin:$xcodegen_dir" \
        bash -c 'xcodegen generate && xcodebuild -project SleepGuard.xcodeproj -scheme SleepGuard -configuration Release -derivedDataPath build build'

# Build SleepGuard.app and install it to /Applications
[group('apps')]
[macos]
sleepguard-install: sleepguard-build
    #!/usr/bin/env bash
    set -euo pipefail
    src="{{ repo_root }}/pkgs/sleepguard/build/Build/Products/Release/SleepGuard.app"
    dest="/Applications/SleepGuard.app"
    launchctl bootout "gui/$(id -u)/com.iceice666.sleepguard" 2>/dev/null || true
    pkill -f "$dest/Contents/MacOS/SleepGuard" 2>/dev/null || true
    pkill -f 'SleepGuard.app/Contents/' 2>/dev/null || true
    rm -rf "$dest"
    cp -R "$src" "$dest"
    # Drop the build copy so the widget (and the app it launches) binds to /Applications.
    lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
    pluginkit -r "$src/Contents/PlugIns/SleepGuardWidgetExtension.appex" 2>/dev/null || true
    "$lsregister" -u "$src" 2>/dev/null || true
    rm -rf "{{ repo_root }}/pkgs/sleepguard/build"
    "$lsregister" -f "$dest"
    pluginkit -a "$dest/Contents/PlugIns/SleepGuardWidgetExtension.appex"
    agent="$HOME/Library/LaunchAgents/com.iceice666.sleepguard.plist"
    if [ -f "$agent" ]; then
        launchctl bootstrap "gui/$(id -u)" "$agent"
        echo "Installed $dest and restarted its launchd agent"
    else
        echo "Installed $dest; run 'just switch' to create its launchd agent"
    fi
