# dotfiles

Multi-host Nix configuration for `m3air`, `framework`, and `homolab`.

One flake drives system configuration, Home Manager, secrets, theme generation, and a small overlay of custom packages. The main tools here are [`nix-darwin`](https://github.com/nix-darwin/nix-darwin), [`home-manager`](https://github.com/nix-community/home-manager), [`sops-nix`](https://github.com/Mic92/sops-nix), [`treefmt-nix`](https://github.com/numtide/treefmt-nix), and [`just`](https://github.com/casey/just).

Detailed repo guidance for coding agents lives in `AGENTS.md`.

## Hosts

| Host | Flake output | Platform | Role |
| --- | --- | --- | --- |
| `m3air` | `.#iceice666@m3air` | `aarch64-darwin` | personal macOS system via `nix-darwin` + Home Manager |
| `framework` | `.#iceice666@framework` | `x86_64-linux` | standalone Home Manager on Linux |
| `homolab` | `.#homolab` | `x86_64-linux` | NixOS server + Home Manager |

## Layout

```text
flake.nix            # flake inputs, overlay, and host outputs
Justfile             # build, switch, validation, secrets, maintenance
treefmt.nix          # formatting configuration
assets/              # wallpapers used by theme generation

common/              # baseline shared across hosts
  configuration/     # shared system-level modules and packages
  home/              # shared Home Manager modules

shared/              # optional reusable modules
  home/              # ghostty, themegen, vscodium, zed

hosts/               # host-specific entrypoints
  m3air/             # macOS host
  framework/         # standalone Home Manager host
  server/            # NixOS host for homolab

pkgs/                # custom overlay packages and helper derivations
sensitive/           # encrypted secrets managed by sops
  shared/            # cross-host secrets
  hosts/server/      # server-only secrets and certificates
```

Composition is structural: `common/ -> shared/ -> hosts/<name>/`.

## Daily Commands

Run commands from the repo root.

Common workflows:

```sh
just build
just switch

just fmt
just check
```

Explicit host targets:

```sh
just m3air-build
just m3air-rebuild

just framework-build
just framework-rebuild

just server-build
just server-rebuild
```

Other useful commands:

```sh
just update
just update-input nixpkgs
just search zed
just gc
just store-size
```

## Validation

There is no unit-test suite here. The narrowest relevant build is the effective test.

- Single host change: dry-build that host.
- `common/home/**`: build each consuming host.
- `shared/home/**`: build each importing host.
- `pkgs/<name>`: build that package directly.

Dry builds:

```sh
sudo darwin-rebuild build --flake .#iceice666@m3air
home-manager build --flake .#iceice666@framework
sudo nixos-rebuild build --flake .#homolab
```

Package example:

```sh
nix build .#packages.aarch64-darwin.equibop-bin
```

## Secrets

Secrets are encrypted with `sops-nix`.

- Shared material lives in `sensitive/shared/`.
- Server material lives in `sensitive/hosts/server/`.
- Rules live in `.sops.yaml`.
- Do not commit plaintext secrets.

Helpers:

```sh
just secret-encrypt sensitive/hosts/server/forgejo.yaml ./forgejo.yaml
just secret-decrypt sensitive/hosts/server/forgejo.yaml
just secret-decrypt sensitive/hosts/server/cloudflared-token.key /tmp/cloudflared-token
```

## Focused Docs

- `AGENTS.md` for detailed repo and editing guidance.
- `shared/home/themegen/README.md` for the theme generation pipeline.

## Acknowledgements

- [win_chan.jpg](./assets/win_chan.jpg): https://x.com/11359OC/status/2040280223632208281/photo/1
- [mzen.png](./assets/mzen.png): https://x.com/Drift0827/status/1990350670445306010
