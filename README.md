# dotfiles

Multi-host Nix configuration for `m3air` and `framework`.

One flake drives system configuration, Home Manager, secrets, theme generation, and a small overlay of custom packages.

See `AGENTS.md` for detailed repo and editing guidance.

## Hosts

| Host | Flake output | Platform | Role |
| --- | --- | --- | --- |
| `m3air` | `.#iceice666@m3air` | `aarch64-darwin` | personal macOS via `nix-darwin` + Home Manager |
| `framework` | `.#framework` | `x86_64-linux` | Framework laptop via NixOS + Home Manager |

## Layout

```text
flake.nix            # flake inputs, overlay, and host outputs
Justfile             # build, switch, validation, secrets, maintenance
treefmt.nix          # formatting (nixfmt + just)
assets/              # wallpapers used by theme generation

common/              # baseline shared across all hosts
  configuration/     # shared Darwin system-level modules
  home/              # shared Home Manager modules and user packages

hosts/               # per-host entrypoints
  m3air/             # macOS
  framework/         # NixOS system + Home Manager modules

pkgs/                # custom overlay packages
sensitive/           # sops-encrypted secrets
```

## Commands

```sh
just build           # dry-build current host
just switch          # apply configuration to current host
just fmt             # format all files
just check           # nix flake check --all-systems
just themegen-generate framework # generate concrete theme cache
just themegen-preview  # preview the current host wallpaper palette
```

Host-specific:

```sh
just m3air-build
just framework-build
just framework-rebuild
```

Framework activation:

```sh
git clone --recurse-submodules https://github.com/iceice666/dotfiles ~/dotfiles
cd ~/dotfiles
just framework-build
just framework-rebuild
```

After the first switch, use `just switch`.

NixOS owns the Framework system, including login/session launch, D-Bus,
PipeWire, NetworkManager, Bluetooth, polkit, greetd/ReGreet, and fingerprint
authentication for greetd and sudo. Home Manager is wired into the NixOS system
configuration for user-level programs and dotfiles.

Enroll fingerprints with:

```sh
fprintd-enroll
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
just secret-encrypt sensitive/hosts/m3air/forgejo.yaml ./forgejo.yaml
just secret-decrypt sensitive/hosts/m3air/forgejo.yaml
just secret-edit sensitive/hosts/m3air/forgejo.yaml
```

Never commit plaintext secrets.

## Docs

- `AGENTS.md` — detailed repo structure, flake inputs, build matrix, code style, conventions.
- `common/home/themegen/README.md` — wallpaper-driven theme generation pipeline.

## Acknowledgements

- [win_chan.jpg](./assets/win_chan.jpg): https://x.com/11359OC/status/2040280223632208281/photo/1
- [mzen.png](./assets/mzen.png): https://x.com/Drift0827/status/1990350670445306010
