# dotfiles

Multi-host Nix dotfiles for my personal machines and homelab.

This repo is built around:

- [nix-darwin](https://github.com/nix-darwin/nix-darwin) for macOS system management
- [home-manager](https://github.com/nix-community/home-manager) for user environment management
- [sops-nix](https://github.com/Mic92/sops-nix) for runtime secret provisioning
- [just](https://github.com/casey/just) for day-to-day workflows
- a small overlay for custom packages plus selected `nixpkgs-unstable` packages

## Hosts

| Host | Flake output | Platform | Scope |
|---|---|---|---|
| `m3air` | `.#iceice666@m3air` | `aarch64-darwin` | full macOS system + Home Manager |
| `framework` | `.#iceice666@framework` | `x86_64-linux` | standalone Home Manager |
| `homolab` | `.#homolab` | `x86_64-linux` | full NixOS system + Home Manager |

## Repository Layout

```text
flake.nix            # flake entrypoint and all outputs
Justfile             # rebuild, validation, secrets, and maintenance workflows
treefmt.nix          # formatter configuration

common/              # imported by every host
  configuration/     # shared system-level packages and modules
  home/              # shared Home Manager modules
    fish/            # fish config + auto-imported function modules

shared/              # opt-in modules used by some hosts
  home/              # editor and app modules such as zed and cursor

hosts/               # per-host entrypoints
  m3air/             # nix-darwin host
  framework/         # standalone Home Manager host
  server/            # NixOS host for homolab

pkgs/                # custom derivations exposed through the overlay
sensitive/           # encrypted and supporting secret material
```

Composition is structural:

```text
common/ -> shared/ -> hosts/<name>/
```

## What It Manages

- Shared shell and CLI tooling through `common/home`: `fish`, `git`, `direnv`, `starship`, `opencode`, `codex`, `mise`, `zellij`, and other CLI basics
- Shared system packages through `common/configuration`
- Optional editor and app modules in `shared/home`, currently Zed and Cursor
- Overlay packages in `flake.nix`, including `equibop-bin` and selected unstable packages
- Server modules in `hosts/server/configuration/services` for Authelia, Cloudflare DDNS, Cloudflare Tunnel, DNSMasq, Docker, Forgejo, Homepage, Ollama, OpenSSH, PostgreSQL/Valkey, RustFS, Traefik, and Woodpecker

## Common Commands

Run everything from the repo root:

```sh
just m3air-rebuild
just framework-rebuild
just server-rebuild

just fmt
just check
just update
just update-input nixpkgs
just search zed
just gc
just store-size
```

Secrets helpers:

```sh
just secret-encrypt sensitive/hosts/server/forgejo.yaml ./forgejo.yaml
just secret-decrypt sensitive/hosts/server/forgejo.yaml
just secret-decrypt sensitive/hosts/server/cloudflared-token.key /tmp/cloudflared-token
```

## Validation

There are no unit tests here. Validation is mostly formatting, flake evaluation, and dry builds.

```sh
just fmt
just check
```

Build a single target without switching:

```sh
sudo darwin-rebuild build --flake .#iceice666@m3air
home-manager build --flake .#iceice666@framework
sudo nixos-rebuild build --flake .#homolab
```

## Mise + Direnv

`direnv` with `nix-direnv` is enabled in `common/home` for every host. `mise` is also installed through Home Manager, so the same project workflow works on `m3air`, `framework`, and the server user environment.

For a simple project with mise:

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

If you prefer a pure `mise` entrypoint, use:

```sh
use mise
```

That requires a `mise.toml` in the project root.

## Host Notes

### `m3air`

First-time setup:

```sh
curl -fsSL https://install.determinate.systems/nix | sh
just m3air-homebrew
just m3air-rebuild
```

Home Manager imports:

- `common/home`
- `shared/home/zed.nix`
- `shared/home/cursor.nix`
- `hosts/m3air/home/karabiner.nix`

If you only changed macOS defaults and want them applied immediately:

```sh
just m3air-activate
```

### `framework`

After installing Nix and Home Manager:

```sh
just framework-rebuild
```

This host uses standalone Home Manager, so packages from `common/configuration/packages.nix` are not installed automatically. The config emits a warning listing the equivalent package set to install with the system package manager.

### `homolab`

On a fresh machine, generate the hardware config on the target host first:

```sh
just server-gen-hardware
just server-rebuild
```

`hosts/server/configuration/hardware-configuration.nix` is machine-specific and should be generated on that server.

## Sensitive Material

Encrypted secrets are managed with `sops-nix`.

- Rules live in `.sops.yaml`
- Server secrets live under `sensitive/hosts/server`
- The NixOS wiring lives in `hosts/server/configuration/sensitive.nix`

Current server secret files include:

- `forgejo.yaml`
- `resend.yaml`
- `rustfs.yaml`
- `woodpecker.yaml`
- `authelia.yaml`
- `cloudflare-ddns.key`
- `cloudflared-token.key`
- `cloudflare-origin-ca/key.pem`
- `cloudflare-origin-ca/root-rsa-cert.pem`

On the server, decryption uses the local age identity at `/var/lib/sops-nix/key.txt`.

## Notes

- `just check` runs `nix flake check --all-systems`
- `just fmt` runs `nix fmt` via `treefmt-nix`
- `framework` intentionally keeps system package installation outside Home Manager
- The server firewall is intentionally restrictive: SSH is LAN-only on port `2222`, and HTTP/HTTPS are limited to LAN plus Cloudflare IP ranges
