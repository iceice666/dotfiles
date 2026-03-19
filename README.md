# dotfiles

Multi-host Nix dotfiles for my personal machines and server.

This repo uses:

- [nix-darwin](https://github.com/nix-darwin/nix-darwin) for macOS system management
- [home-manager](https://github.com/nix-community/home-manager) for user environment management
- [sops-nix](https://github.com/Mic92/sops-nix) for runtime secret provisioning
- [just](https://github.com/casey/just) for common workflows
- a small local overlay for custom and unstable packages

## Hosts

| Host | Flake output | Platform | What it manages |
|---|---|---|---|
| `m3air` | `.#iceice666@m3air` | `aarch64-darwin` | full macOS system + home-manager |
| `framework` | `.#iceice666@framework` | `x86_64-linux` | standalone home-manager only |
| `homolab` | `.#homolab` | `x86_64-linux` | full NixOS system + home-manager |

## Layout

```text
flake.nix            # flake entrypoint and all outputs
Justfile             # rebuild / check / update workflows
treefmt.nix          # formatter configuration

common/              # imported everywhere
  configuration/     # shared system-level packages/modules
  home/              # shared home-manager modules
    fish/            # fish config + auto-imported functions

shared/              # opt-in modules used by some hosts
  home/              # editor/app modules such as zed and cursor

hosts/               # per-host entrypoints
  m3air/             # nix-darwin host
  framework/         # standalone home-manager host
  server/            # NixOS host for homolab

pkgs/                # custom derivations exposed through the overlay
secrets/             # SOPS-encrypted host secrets
```

Composition is structural:

```text
common/ -> shared/ -> hosts/<name>/
```

## What It Manages

- Shared shell and CLI tooling through Home Manager: `fish`, `git`, `direnv`, `starship`, `opencode`, and `codex`
- Shared system packages through [`common/configuration`](/home/iceice666/dotfiles/common/configuration)
- Optional editor/app modules in [`shared/home`](/home/iceice666/dotfiles/shared/home), currently Zed and Cursor
- Local overlay packages and pinned unstable packages from `nixpkgs-unstable`
- A custom `equibop-bin` derivation in [`pkgs/equibop-bin`](/home/iceice666/dotfiles/pkgs/equibop-bin/default.nix)
- NixOS server services in [`hosts/server/configuration/services`](/home/iceice666/dotfiles/hosts/server/configuration/services): Caddy, Forgejo, PostgreSQL, Valkey, Docker, Ollama, Cloudflare DDNS, Cloudflare Tunnel, Cloudflare IP allowlists, and OpenSSH

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

## Devenv + Direnv

`direnv` with `nix-direnv` is enabled in the shared home-manager config for all hosts.
`devenv` is also installed through home-manager, so the same workflow works on `m3air`,
`framework`, and the server user environment.

In any project where you want an automatic dev shell:

```sh
cat > .envrc <<'EOF'
use flake
EOF

cat > devenv.nix <<'EOF'
{ pkgs, ... }:
{
  packages = with pkgs; [
    git
    just
  ];

  enterShell = ''
    echo "devenv loaded"
  '';
}
EOF

direnv allow
devenv shell
```

If you prefer a pure `devenv` entrypoint instead of `use flake`, use this `.envrc`:

```sh
use devenv
```

That requires a `devenv.nix` (or `devenv.yaml`) in the project root. After editing
either file, run `direnv reload` or re-enter the directory.

## Validation

There are no unit tests here. Validation is mostly formatting, flake evaluation, and dry builds.

```sh
just fmt
just check
```

To evaluate a single target without switching:

```sh
sudo darwin-rebuild build --flake .#iceice666@m3air
home-manager build --flake .#iceice666@framework
sudo nixos-rebuild build --flake .#homolab
```

## Host Notes

### `m3air`

First-time setup:

```sh
curl -fsSL https://install.determinate.systems/nix | sh
just m3air-homebrew
just m3air-rebuild
```

This host imports:

- [`common/home`](/home/iceice666/dotfiles/common/home)
- [`shared/home/zed.nix`](/home/iceice666/dotfiles/shared/home/zed.nix)
- [`shared/home/cursor.nix`](/home/iceice666/dotfiles/shared/home/cursor.nix)
- [`hosts/m3air/home/karabiner.nix`](/home/iceice666/dotfiles/hosts/m3air/home/karabiner.nix)

If you only changed macOS defaults and want them applied immediately:

```sh
just m3air-activate
```

### `framework`

After installing Nix and Home Manager:

```sh
just framework-rebuild
```

This host uses standalone Home Manager, so packages from [`common/configuration/packages.nix`](/home/iceice666/dotfiles/common/configuration/packages.nix) are not installed automatically. The config emits a warning listing the same package set to install with the system package manager.

### `homolab`

On a fresh machine, generate hardware config on the target host first:

```sh
just server-gen-hardware
just server-rebuild
```

[`hosts/server/configuration/hardware-configuration.nix`](/home/iceice666/dotfiles/hosts/server/configuration/hardware-configuration.nix) is machine-specific and should be generated on that server.

## Secrets

Secrets are managed with `sops-nix`.

- Repo guidance lives in [`sops_guide.md`](/home/iceice666/dotfiles/sops_guide.md)
- SOPS rules live in [`.sops.yaml`](/home/iceice666/dotfiles/.sops.yaml)
- Current server secrets live under [`secrets/hosts/server`](/home/iceice666/dotfiles/secrets/hosts/server)

Expected server secret files:

- `forgejo.yaml`
- `cloudflare-ddns.key`
- `cloudflared-token.key`

On the server, decryption uses a local age identity at `/var/lib/sops-nix/key.txt`.

## Notes

- `just check` runs `nix flake check --all-systems`
- `just fmt` runs `nix fmt` via `treefmt-nix`
- `framework` deliberately keeps system package installation outside Home Manager
- The server firewall is intentionally restrictive: SSH is LAN-only on port `2222`, and HTTP/HTTPS are limited to LAN plus Cloudflare IP ranges
