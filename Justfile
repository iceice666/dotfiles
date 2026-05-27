# Dotfiles management recipes

set shell := ["bash", "-euo", "pipefail", "-c"]

repo_root := justfile_directory()
m3air_flake := ".#iceice666@m3air"
framework_flake := ".#framework"
framework_build_attr := ".#nixosConfigurations.framework.config.system.build.toplevel"
framework_kaguya_cache := repo_root / ".cache/kaguya/framework"
homolab_flake := ".#homolab"
homolab_host := "iceice666@homolab"
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
    sudo nixos-rebuild switch --flake {{ framework_flake }} --override-input kaguya-cache path:{{ framework_kaguya_cache }}

# Dry-build the M3 Air nix-darwin configuration
[group('host')]
[macos]
build:
    darwin-rebuild build --flake {{ m3air_flake }}

# Dry-build the Framework NixOS configuration
[group('host')]
[linux]
build: _kaguya-cache
    nix build {{ framework_build_attr }} --override-input kaguya-cache path:{{ framework_kaguya_cache }}

# Set the Framework NixOS configuration for next boot
[group('host')]
[linux]
boot: _kaguya-cache
    test -e /etc/NIXOS || { echo "Framework boot activation requires NixOS." >&2; exit 1; }
    sudo nixos-rebuild boot --flake {{ framework_flake }} --override-input kaguya-cache path:{{ framework_kaguya_cache }}

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

# Apply the homolab NixOS configuration over SSH
[group('host')]
homolab-switch:
    nixos-rebuild switch --flake {{ homolab_flake }} \
        --target-host {{ homolab_host }} \
        --build-host {{ homolab_host }} \
        --use-remote-sudo

# Stage the homolab NixOS configuration for next boot over SSH
[group('host')]
homolab-boot:
    nixos-rebuild boot --flake {{ homolab_flake }} \
        --target-host {{ homolab_host }} \
        --build-host {{ homolab_host }} \
        --use-remote-sudo

# Dry-build the homolab NixOS configuration on the server
[group('host')]
homolab-build:
    nixos-rebuild build --flake {{ homolab_flake }} \
        --build-host {{ homolab_host }}

# Refresh hardware-configuration.nix from the live homolab server
[group('host')]
homolab-gen-hardware:
    ssh {{ homolab_host }} sudo nixos-generate-config --show-hardware-config \
        > {{ repo_root }}/hosts/homolab/configuration/hardware-configuration.nix

# Smoke-check the homolab OpenAI-compatible LLM endpoint
[group('host')]
homolab-llama-smoke:
    LLAMA_SWAP_BASE_URL="${LLAMA_SWAP_BASE_URL:-http://homolab:11434}" \
        {{ scripts }}/llama-swap-smoke

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

# Generate a local concrete theme cache for M3 Air inspection
[group('theme')]
[macos]
theme:
    @{{ scripts }}/themegen-cache generate m3air {{ repo_root }}/assets/win_chan.jpg

# Generate a local concrete theme cache for Framework inspection
[group('theme')]
[linux]
theme:
    @{{ scripts }}/themegen-cache generate framework {{ repo_root }}/assets/mzen.png

# Render an HTML preview for the current or specified wallpaper palette
[group('theme')]
[macos]
theme-preview image='':
    @{{ scripts }}/themegen-cache preview m3air '{{ image }}'

# Render an HTML preview for the current or specified wallpaper palette
[group('theme')]
[linux]
theme-preview image='':
    @{{ scripts }}/themegen-cache preview framework '{{ image }}'

# Update all flake inputs, or selected inputs when names are passed
[group('flake')]
update *inputs:
    nix flake update {{ inputs }}

# Ask a coding agent to update custom package versions and commit the result
[group('flake')]
update-custom-pkgs agent='codex':
    {{ scripts }}/update-custom-pkgs-agent '{{ agent }}' '{{ repo_root }}'

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
