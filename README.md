# dotfiles

Multi-host Nix configuration for `m3air` and `framework`.

One flake drives system configuration, Home Manager, secrets, wallpaper-derived theme generation, dev shells, and a small overlay of custom packages.

See `AGENTS.md` for detailed repo and editing guidance.

## Hosts

| Host | Flake output | Platform | Role |
| --- | --- | --- | --- |
| `m3air` | `.#iceice666@m3air` | `aarch64-darwin` | personal macOS via `nix-darwin` + Home Manager |
| `framework` | `.#framework` | `x86_64-linux` | Framework laptop via NixOS + Home Manager |

## Layout

```text
flake.nix            # flake inputs, overlay, dev shells, and host outputs
Justfile             # thin task runner for build, switch, validation, secrets, maintenance
scripts/             # shell implementations for complex just recipes
treefmt.nix          # formatting (nixfmt + just)
assets/              # wallpapers and host images used by theme generation

common/              # baseline shared across all hosts
  configuration/     # shared Darwin system-level modules
  home/              # shared Home Manager modules and user packages

hosts/               # per-host entrypoints
  m3air/             # macOS
  framework/         # NixOS system + Home Manager modules

themegen/            # $HOME-relative theme templates rendered by Nix derivations
pkgs/                # custom overlay packages and the themegen Rust CLI
sensitive/           # sops-encrypted secrets
```

## Commands

```sh
just build           # dry-build current platform host
just switch          # apply configuration to current platform host
just boot            # set Framework for next boot, Linux only
just fmt             # format all files
just fmt-check       # check Justfile formatting
just check           # format, Justfile metadata, and flake checks
just theme           # generate a local concrete theme cache for inspection
just kaguya          # refresh Framework Kaguya browser cache from homolab
just theme-preview   # render and open this platform's wallpaper palette preview
```

`just` recipes are platform-gated: macOS maps to `m3air`, and Linux maps to
`framework`. The same `build` and `switch` recipe names have separate
`[macos]` and `[linux]` implementations.

M3 Air helper recipes are available only on macOS:

```sh
just m3air-homebrew
just m3air-activate
```

Framework activation:

```sh
git clone --recurse-submodules https://github.com/iceice666/dotfiles ~/dotfiles
cd ~/dotfiles
just build
just switch
```

After the first switch, use `just switch`.

NixOS owns the Framework system, including login/session launch, D-Bus,
PipeWire, NetworkManager, Bluetooth, polkit, greetd/ReGreet, and fingerprint
authentication for greetd and sudo. Home Manager is wired into the NixOS system
configuration for user-level programs, Niri, Eww, nirinit session persistence,
and dotfiles.

Enroll fingerprints with:

```sh
fprintd-enroll
```

Other:

```sh
just update
just update nixpkgs
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
- `common/home/rime/README.md` — Frost/Rime data wiring and Traditional Chinese model setup.
- `common/home/themegen/README.md` — wallpaper-driven theme generation pipeline.

## Acknowledgements

- [win_chan.jpg](./assets/win_chan.jpg): https://x.com/11359OC/status/2040280223632208281/photo/1
- [mzen.png](./assets/mzen.png): https://x.com/Drift0827/status/1990350670445306010
