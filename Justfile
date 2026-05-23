# Dotfiles management recipes

set shell := ["bash", "-euo", "pipefail", "-c"]

repo_root := justfile_directory()
m3air_flake := ".#iceice666@m3air"
framework_flake := ".#framework"
framework_build_attr := ".#nixosConfigurations.framework.config.system.build.toplevel"
scripts := repo_root / "scripts"

# Apply the M3 Air nix-darwin configuration
[group('host')]
[macos]
switch: theme
    sudo darwin-rebuild switch --flake {{ m3air_flake }} --override-input themegen-cache path:{{ repo_root }}/.cache/themegen/m3air

# Apply the Framework NixOS configuration
[group('host')]
[linux]
switch: theme kaguya
    test -e /etc/NIXOS || { echo "Framework switch requires NixOS. The legacy standalone Home Manager path was removed." >&2; exit 1; }
    sudo nixos-rebuild switch --flake {{ framework_flake }} --override-input themegen-cache path:{{ repo_root }}/.cache/themegen/framework --override-input kaguya-cache path:{{ repo_root }}/.cache/kaguya/framework

# Dry-build the M3 Air nix-darwin configuration
[group('host')]
[macos]
build: theme
    darwin-rebuild build --flake {{ m3air_flake }} --override-input themegen-cache path:{{ repo_root }}/.cache/themegen/m3air

# Dry-build the Framework NixOS configuration
[group('host')]
[linux]
build: theme kaguya
    nix build {{ framework_build_attr }} --override-input themegen-cache path:{{ repo_root }}/.cache/themegen/framework --override-input kaguya-cache path:{{ repo_root }}/.cache/kaguya/framework

# Set the Framework NixOS configuration for next boot
[group('host')]
[linux]
boot: theme kaguya
    test -e /etc/NIXOS || { echo "Framework boot activation requires NixOS." >&2; exit 1; }
    sudo nixos-rebuild boot --flake {{ framework_flake }} --override-input themegen-cache path:{{ repo_root }}/.cache/themegen/framework --override-input kaguya-cache path:{{ repo_root }}/.cache/kaguya/framework

# Copy the latest Kaguya browser build from homolab into the local Nix path input cache
[group('host')]
[linux]
kaguya:
    {{ scripts }}/kaguya-cache

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
    @{{ scripts }}/themegen-cache generate m3air {{ repo_root }}/assets/win_chan.jpg

# Generate concrete theme files for Framework
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
