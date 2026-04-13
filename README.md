# dotfiles

Multi-host Nix configuration for `m3air`, `framework`, and `homolab`.

One flake drives system configuration, Home Manager, secrets, theme generation, and a small overlay of custom packages.

See `AGENTS.md` for detailed repo and editing guidance.

## Hosts

| Host | Flake output | Platform | Role |
| --- | --- | --- | --- |
| `m3air` | `.#iceice666@m3air` | `aarch64-darwin` | personal macOS via `nix-darwin` + Home Manager |
| `framework` | `.#iceice666@framework` | `x86_64-linux` | standalone Home Manager on Void Linux |
| `homolab` | `.#homolab` | `x86_64-linux` | NixOS server + Home Manager |

## Layout

```text
flake.nix            # flake inputs, overlay, and host outputs
Justfile             # build, switch, validation, secrets, maintenance
treefmt.nix          # formatting (nixfmt + just)
assets/              # wallpapers used by theme generation

common/              # baseline shared across all hosts
  configuration/     # shared system-level modules and packages
  home/              # shared Home Manager modules (fish, opencode, ...)

shared/              # optional reusable modules
  home/              # ghostty, themegen, vscodium, zed

hosts/               # per-host entrypoints
  m3air/             # macOS
  framework/         # standalone Home Manager
  server/            # NixOS (homolab)

pkgs/                # custom overlay packages
sensitive/           # sops-encrypted secrets
```

## Commands

```sh
just build           # dry-build current host
just switch          # apply configuration to current host
just fmt             # format all files
just check           # nix flake check --all-systems
```

Host-specific:

```sh
just m3air-build / just m3air-rebuild
just framework-build / just framework-rebuild
just server-build / just server-rebuild
```

Other:

```sh
just update
just update-input nixpkgs
just search <query>
just gc
just store-size
```

## Secrets

Encrypted with [`sops-nix`](https://github.com/Mic92/sops-nix). Rules in `.sops.yaml`.

```sh
just secret-encrypt sensitive/hosts/server/forgejo.yaml ./forgejo.yaml
just secret-decrypt sensitive/hosts/server/forgejo.yaml
just secret-edit sensitive/hosts/server/forgejo.yaml
```

Never commit plaintext secrets.

## Docs

- `AGENTS.md` — detailed repo structure, flake inputs, build matrix, code style, conventions.
- `shared/home/themegen/README.md` — wallpaper-driven theme generation pipeline.

## Acknowledgements

- [win_chan.jpg](./assets/win_chan.jpg): https://x.com/11359OC/status/2040280223632208281/photo/1
- [mzen.png](./assets/mzen.png): https://x.com/Drift0827/status/1990350670445306010
