# dotfiles

Personal multi-host Nix configuration for my laptop, Linux box, and homelab server.

One flake drives system configuration, user environment, secrets, theme generation, and a small set of custom packages.

This repo is built around:

- [nix-darwin](https://github.com/nix-darwin/nix-darwin) for macOS system management
- [home-manager](https://github.com/nix-community/home-manager) for user environment management
- [sops-nix](https://github.com/Mic92/sops-nix) for runtime secret provisioning
- [treefmt-nix](https://github.com/numtide/treefmt-nix) for formatting
- [just](https://github.com/casey/just) for day-to-day workflows
- a small overlay for custom packages plus selected `nixpkgs-unstable` packages

Repository-specific instructions for coding agents live in `AGENTS.md`.

## Hosts

| Host | Flake output | Platform | Role |
|---|---|---|---|
| `m3air` | `.#iceice666@m3air` | `aarch64-darwin` | personal macOS system + Home Manager |
| `framework` | `.#iceice666@framework` | `x86_64-linux` | standalone Home Manager on Linux |
| `homolab` | `.#homolab` | `x86_64-linux` | NixOS server + Home Manager |

## Mental Model

Composition is structural:

```text
common/ -> shared/ -> hosts/<name>/
```

- `common/` is the baseline used everywhere.
- `shared/` contains optional modules reused by some hosts.
- `hosts/<name>/` holds machine-specific choices and entrypoints.

The README focuses on how to operate the repo, not every imported file. The source tree is the authority for exact module wiring.

## Repository Layout

```text
flake.nix            # flake inputs, overlay, and host outputs
Justfile             # rebuild, validation, secrets, and maintenance workflows
treefmt.nix          # formatter configuration
assets/              # wallpaper/source images used by theme generation

common/              # baseline shared by every host
  configuration/     # shared system packages and system-level config
  home/              # shared Home Manager modules
    fish/            # fish config + auto-imported function modules

shared/              # optional modules reused by some hosts
  home/              # shared Home Manager modules such as zed, themegen, vscodium
    themegen/        # Nix theme generators rendered from wallpaper-derived palettes

hosts/               # host entrypoints
  m3air/             # nix-darwin host
  framework/         # standalone Home Manager host
  server/            # NixOS host for homolab

pkgs/                # overlay packages: equibop-bin, mise-bin, themegen
sensitive/           # encrypted secrets and supporting certificate/key material
```

## What It Manages

- Shared CLI and shell baseline in `common/home`, including `fish`, `git`, `direnv`, `starship`, `opencode`, `mise`, `zellij`, and small fish helpers.
- Shared system packages in `common/configuration` for hosts that support `environment.systemPackages`.
- Optional shared Home Manager modules in `shared/home`, currently including Zed, wallpaper-driven theme generation, and VSCodium.
- Per-host behavior in `hosts/`, including macOS defaults and Homebrew integration on `m3air`, standalone Home Manager on `framework`, and the homelab service stack on `homolab`.
- Custom overlay packages exposed through `flake.nix`, currently `equibop-bin`, `mise-bin`, and `themegen`.
- Server services behind Traefik and SSO, including Forgejo, Woodpecker, Dynacat, Ollama, PostgreSQL, Valkey, RustFS, dnsmasq, Cloudflare DDNS, and the Cloudflare tunnel.

## Focused Docs

- `shared/home/themegen/README.md` explains the themegen pipeline, the shared Nix template layer, and how to change or validate themed apps.

## Daily Commands

Run everything from the repo root.

Current host:

```sh
just build
just switch
```

These auto-detect the current machine and select the matching flake target.

Explicit host builds and rebuilds:

```sh
just m3air-build
just m3air-rebuild

just framework-build
just framework-rebuild

just server-build
just server-rebuild
```

Maintenance:

```sh
just fmt
just check
just update
just update-input nixpkgs
just search zed
just gc
just store-size
```

Host-specific helpers:

```sh
just m3air-homebrew
just m3air-activate
just server-gen-hardware
```

`just server-build`, `just server-rebuild`, and `just server-gen-hardware` are guarded and refuse to run on non-server hosts.

## Validation

There is no unit-test suite here. The narrowest relevant build is the effective test.

Quick rules:

- Formatting-sensitive changes: `just fmt`
- Flake wiring or shared-module changes: `just check`
- Single host change: dry-build that host
- Single package change: build the affected package directly

Dry builds:

```sh
sudo darwin-rebuild build --flake .#iceice666@m3air
home-manager build --flake .#iceice666@framework
sudo nixos-rebuild build --flake .#homolab
```

Package-only example:

```sh
nix build .#packages.aarch64-darwin.equibop-bin
```

## Direnv And Mise

`direnv` with `nix-direnv` is enabled in `common/home` for every host. `mise` is also installed everywhere, so the same basic workflow works across `m3air`, `framework`, and the server user environment.

Simple example:

```sh
cat > .envrc <<'EOF'
use mise
EOF

cat > mise.toml <<'EOF'
[tools]
node = "20"
just = "latest"

[tasks]
hello = "echo hello from mise"
EOF

direnv allow
mise run hello
```

## Host Notes

### `m3air`

This is the full macOS host managed by `nix-darwin` plus Home Manager.

- Uses `common/` as the baseline, then layers in macOS-specific defaults, Homebrew-managed macOS-only apps, and user modules like Zed, theme generation, VSCodium, wallpaper refresh, and Karabiner config.
- The generated theme is based on `assets/win_chan.jpg`.

First-time setup:

```sh
curl -fsSL https://install.determinate.systems/nix | sh
just m3air-homebrew
just switch
```

If you only changed macOS defaults and want them applied immediately:

```sh
just m3air-activate
```

### `framework`

This host uses standalone Home Manager on Linux.

- Reuses `common/home` and selected shared modules, but does not get `common/configuration/packages.nix` automatically because `environment.systemPackages` is unavailable in standalone Home Manager mode.
- The config emits a warning listing the equivalent package set to install with the system package manager.
- The generated theme is based on `assets/mzen.png`.

After installing Nix and Home Manager:

```sh
just switch
```

### `homolab`

This is the NixOS server host exposed as `.#homolab`.

- Runs the server service stack in `hosts/server/configuration/services`, including Traefik, Authelia, Forgejo, Woodpecker, Dynacat, Ollama, PostgreSQL/Valkey, RustFS, DNS, and Cloudflare integrations.
- Uses Home Manager for the `iceice666` user environment on top of the NixOS configuration.
- Admin SSH on port `2222` is LAN-only.
- Forgejo SSH on port `22` stays public.
- HTTP and HTTPS are limited to LAN plus Cloudflare IP ranges.

On a fresh machine, generate the hardware config on the target host first:

```sh
just server-gen-hardware
just switch
```

`hosts/server/configuration/hardware-configuration.nix` is machine-specific and should only be generated on that server.

## Secrets

Encrypted secrets are managed with `sops-nix`.

- Rules live in `.sops.yaml`.
- Encrypted server material lives under `sensitive/hosts/server`.
- NixOS secret wiring lives in `hosts/server/configuration/sensitive.nix`.
- On the server, decryption uses the local age identity at `/var/lib/sops-nix/key.txt`.
- Do not commit plaintext secrets.

Current server secret files include:

```text
authelia.yaml
cloudflare-ddns.key
cloudflare-origin-ca/cert.pem
cloudflare-origin-ca/key.pem
cloudflare-origin-ca/root-rsa-cert.pem
cloudflared-token.key
forgejo.yaml
resend.yaml
rustfs.yaml
woodpecker.yaml
```

Helpers:

```sh
just secret-encrypt sensitive/hosts/server/forgejo.yaml ./forgejo.yaml
just secret-decrypt sensitive/hosts/server/forgejo.yaml
just secret-decrypt sensitive/hosts/server/cloudflared-token.key /tmp/cloudflared-token
```

## Notes

- `just build` auto-detects the current host and runs the matching dry build.
- `just switch` auto-detects the current host and applies the matching configuration.
- `just check` runs `nix flake check --all-systems`.
- `just fmt` runs `nix fmt` via `treefmt-nix`.
- `framework` intentionally keeps system package installation outside Home Manager.
- Theme generation renders Ghostty, Zed, starship, opencode, and terminal colors from the host wallpaper.
