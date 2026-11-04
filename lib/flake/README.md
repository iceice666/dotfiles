# Local flake framework

`flake.nix` only declares inputs and imports `lib/flake`. Framework files are
split by output responsibility:

- `hosts.nix` **auto-discovers** `hosts/*/host.nix` via `builtins.readDir` — no hand-maintained list.
- `mk-host.nix` builds `nixosSystem`, `darwinSystem`, or standalone `homeManagerConfiguration` outputs. It reads `host.features` to inject the matching shared modules.
- `home-manager.nix` generates the `home-manager = { … };` module from host features and home imports — no per-host duplication.
- `overlays/` registers custom packages, split by purpose (see below).
- `pkgs.nix` defines `unstablePkgsFor`.
- `systems.nix` is the single source of truth for the supported system list.
- `deploy.nix` generates deploy-rs nodes from host deploy metadata.
- `dev-shells.nix` and `formatters.nix` consume `systems.nix`.

## Hosts and feature flags

Host specs own: `name`, `kind`, `system`, `username`, `homeDirectory`, optional
`modules`, `homeModules`, `features`, `extraSpecialArgs`, and optional `deploy`.
`kind` may be `nixos`, `darwin`, or `home-manager`.

| Feature flag | What it injects |
|---|---|
| `homeManager` | system-module Home Manager wiring for NixOS/nix-darwin |
| `sops` | system sops module plus HM sharing, or standalone HM sops module |
| `gui` | `common/home-gui` |
| `themegen` | `common/home-gui/themegen` |
| `rime` | `common/home-gui/rime` |
| `devEnv` | `common/home-base/dev-env.nix` |
| `pi` | `common/home-base/pi.nix` (binary and configuration) |

Shared module injection:

- `common/system/` — NixOS and nix-darwin hosts. Standalone Home Manager hosts do not import system modules.
- `common/system-darwin/` / `common/system-nixos/` — darwin-only / NixOS-only.
- `common/home-base/` — CLI baseline for every `features.homeManager = true` host.
- `common/home-alpine/` — root-only Lix, direct sops activation, and Alpine root-shell wiring for standalone Home Manager hosts.
- `common/home-gui/` — `features.gui = true`; server hosts do not import it.

**Adding a host:** create `hosts/<new>/host.nix` with a
`{ inputs, dotfiles, name }:` signature, declare `features`, and add
`homeModules = [ ./home ]`. The host appears as a flake output automatically.

## Inputs

`flake.nix` is the source of truth. Notable pins:

- `nixpkgs` tracks `nixos-26.05`; `nix-darwin` and `home-manager` follow the matching 26.05 branches.
- `nixpkgs-unstable` is used through `unstablePkgsFor` and for specific packages.
- `ags` is pinned to `v3.1.2` (Framework GTK4 shell); its matching Astal follows the upstream lock.
- `ghostty` is pinned to a commit of the `iceice666/ghostty` fork (vertical tabs); see `pkgs/ghostty-bin/README.md`.
- `pirc` is release-pinned and follows `nixpkgs-unstable` (its `bun.lock` needs Bun 1.4). Its overlay adds `pkgs.pirc-gateway` (used by lumo's `pirc.nix`) and `pkgs.pirc-node` (homolab/WSL runs a manually built node). To upgrade, bump the tag in `flake.nix`, run `just update pirc`, and back up both services' state first.
- `niri-scratchpad-helper` and `reimu-on-starlit-water` are non-flake sources built by `overlays/linux-gui.nix`.

## Outputs

| Output | Type |
|---|---|
| `darwinConfigurations.m5pro` | nix-darwin configuration |
| `nixosConfigurations.framework` | NixOS configuration |
| `nixosConfigurations.framework-installer` | minimal UEFI Framework reinstall ISO (`config.system.build.isoImage`) |
| `homeConfigurations.lumo` | Alpine root Home Manager data+apps + DNS + edge configuration |
| `homeConfigurations.worker` | Alpine root Home Manager disposable-work / agent-runtime host |
| `deploy` | deploy-rs node definitions for `framework`, `lumo`, and `worker` |
| `checks.x86_64-linux` | deploy-rs schema validation checks |
| `devShells.<system>.default` | Rust/themegen development shell (includes `deploy`) |
| `formatter.<system>` | treefmt |
| `packages.<system>.*` | standalone overlay packages (`nix build .#themegen`, …) |

## Overlays

`overlays/default.nix` composes, in order:

- `lix.nix` — inherits `nix-eval-jobs`, `nix-fast-build`, `nixpkgs-review` from `pkgs.lixPackageSets.stable`.
- `nodejs.nix` — temporary official Node.js binary pins through `pkgs/nodejs-bin` (24.x for the CLI/Pi, 22.x for consumers such as Bitwarden). Remove once both locked package sets provide equivalent fixes; keep `scripts/tests/test-nodejs-security.mjs`. See `docs/tls-trust.md` and `pkgs/nodejs-bin/README.md`.
- `binaries.nix` — repo packages under `pkgs/`.
- `linux-gui.nix` — Linux-only packages (`niri-scratchpad-helper`, `reimu-on-starlit-water`). Attributes are omitted, not thrown, on non-Linux.
- `global-patches.nix` — the filtered `dotfiles-cacert` bundle, the temporary Bun canary pin (see `docs/tls-trust.md`), and the `direnv` build fix (strips `-linkmode=external`).
- the `pirc` input overlay.
- an inline `ghostty` selection: the fork's flake package on Linux, `pkgs/ghostty-bin` on Darwin.

Package notes:

- `reimu-on-starlit-water` builds with the `nixpkgs-unstable` Rust toolchain.
- `helium-bin` packages the Helium macOS DMG on Darwin and the Linux AppImage (via `appimageTools`) on Linux; m5pro and Framework use it as their default browser.

## `unstablePkgsFor`

Imports `nixpkgs-unstable` with `allowUnfree = true` and `cudaSupport = true`,
with the overlay applied. Shared Home Manager modules use it for packages such
as `bun` and `sops`.
