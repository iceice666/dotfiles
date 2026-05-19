# AGENTS.md - Repository Guide

This repository is a multi-host Nix dotfiles setup built around `flake.nix`, `nix-darwin`, `home-manager`, `sops-nix`, `treefmt-nix`, and `just`.
Use this file as the working agreement for coding agents editing this repo.

`README.md` is the concise operator-facing overview. Keep the detailed implementation and editing guidance here.

## Repository Shape

```text
flake.nix            # flake inputs, overlay, dev shells, and host outputs
Justfile             # build, switch, themegen, validation, secrets, maintenance
treefmt.nix          # formatter configuration (nixfmt + just)
assets/              # wallpaper/source images and host avatar assets

common/              # baseline shared across all hosts
  configuration/     # shared system-level modules for darwin hosts
    default.nix      # sets Lix and shared Darwin system settings
  home/              # shared Home Manager baseline (imported by all hosts)
    default.nix      # shared programs, sops age key path, state version
    packages.nix     # shared user package list
    user.nix
    fish/            # fish config + auto-imported function modules (12 functions)
    app-defaults.nix # shared app preference files
    dev-env.nix      # shared development environment config
    ghostty.nix      # shared Ghostty config
    rime/            # Rime Frost setup with Traditional Chinese octagram model
    themegen/        # wallpaper-driven theme generation and templates
      templates/     # ghostty, equibop, starship, zed, vscode, terminal-sequences
    vscodium.nix     # VSCodium config + marketplace wiring
    zed.nix          # Zed config

themegen/            # root-level plain theme templates, split by common/host
  common/            # shared $HOME-relative templates for shells/editors/terminal
  m3air/             # macOS-only $HOME-relative templates
  framework/         # Linux-only $HOME-relative templates for GTK/Qt/fuzzel/Eww
  preview.html       # HTML palette preview template

hosts/               # per-host entrypoints
  m3air/             # macOS via nix-darwin
    configuration/   # default.nix, system-defaults.nix
    home/            # default.nix, appearance, default apps, karabiner, wallpaper
  framework/         # NixOS system with Home Manager
    configuration/   # active NixOS system entrypoint, hardware, GRUB theme
    home/            # GUI/Niri/Eww Home Manager modules imported by NixOS

pkgs/                # overlay packages
  codex-cli-bin/     # official prebuilt OpenAI Codex CLI releases
  default-browser/   # macOS default browser helper
  equibop-bin/       # Equibop binary
  rime-frost/        # Rime Frost schema data
  rime-octagram-zh-hant-essay-bgw/ # Traditional Chinese octagram grammar model
  themegen/          # Rust-based theme generator (Cargo project)
  utiluti/           # macOS utility for default app associations
  zed-bin/           # Zed official prebuilt releases
  zen-bin/           # Zen Browser Darwin package

sensitive/           # encrypted secret and certificate material managed by sops
  shared/            # cross-host secrets
```

Composition is structural: `common/ -> hosts/<name>/`.

## Flake Details

### Inputs

| Input | Source | Follows nixpkgs |
|---|---|---|
| `nixpkgs` | `github:NixOS/nixpkgs/nixos-25.11` | — |
| `nixpkgs-unstable` | `github:NixOS/nixpkgs/nixpkgs-unstable` | no |
| `nix-darwin` | `github:nix-darwin/nix-darwin/nix-darwin-25.11` | yes |
| `home-manager` | `github:nix-community/home-manager/release-25.11` | yes |
| `treefmt-nix` | `github:numtide/treefmt-nix` | yes |
| `sops-nix` | `github:Mic92/sops-nix` | yes |
| `nirinit` | `github:amaanq/nirinit` | yes |
| `themegen-cache` | `path:./common/home/themegen/empty-cache` | no |
| `zen-browser` | `github:youwen5/zen-browser-flake` | yes |
`self.submodules = true` is set so Git submodules are fetched.

`themegen-cache` is a placeholder flake input. Build and switch recipes replace
it with `path:$PWD/.cache/themegen/<host>` after running
`just themegen-generate <host>`.

### Outputs

| Output | Type |
|---|---|
| `darwinConfigurations."iceice666@m3air"` | nix-darwin configuration |
| `nixosConfigurations.framework` | NixOS configuration |
| `homeConfigurations."iceice666@framework"` | legacy standalone Home Manager configuration |
| `devShells.aarch64-darwin.default` / `devShells.x86_64-linux.default` | Rust/themegen development shell |
| `formatter.aarch64-darwin` / `formatter.x86_64-linux` | treefmt |

There are **no `packages.*` outputs** in the flake. Overlay packages are only accessible through host configurations, not as standalone flake outputs.

### Overlay

Custom packages registered in the overlay: `codex-cli-bin`, `default-browser`, `equibop-bin`, `rime-frost`, `rime-octagram-zh-hant-essay-bgw`, `themegen`, `utiluti`, `zed-bin`, `zen-bin`.

The overlay also follows Lix's advanced setup guidance by inheriting Lix-backed
`colmena`, `nix-eval-jobs`, `nix-fast-build`, and `nixpkgs-review`
from `pkgs.lixPackageSets.stable`.

Additionally:
- `zen-bin` uses the `zen-browser` flake on Linux and the local Darwin package under `pkgs/zen-bin`.
- `linux_zen_7_0` and `linuxPackages_zen_7_0` pin the Framework kernel family.
- `eww` is patched on Linux so app windows can paint transparent backgrounds.
- `direnv` is overridden to strip `-linkmode=external` from its Makefile (build fix).

### `unstablePkgsFor`

A helper is defined that imports `nixpkgs-unstable` with `allowUnfree = true` and `cudaSupport = true`, with the overlay applied. Used by shared Home Manager modules to pull in `bun` and `sops` from unstable.

## Build, Format, and Validation Commands

Run commands from the repository root.

## Framework NixOS Setup

`framework` is a NixOS machine managed by the `nixosConfigurations.framework`
flake output. The system imports `home-manager.nixosModules.home-manager`, so
Framework user configuration still lives under `hosts/framework/home/`, but the
active switch path is the NixOS system target.

Build and activate the Framework system:

```sh
just framework-build
just framework-rebuild
```

Prefer these `just` recipes over direct `nix build`, `darwin-rebuild`,
`nixos-rebuild`, or `home-manager` commands. The recipes run required
pre-build steps such as `themegen-generate` and pass the correct flake input
overrides.

Direct NixOS commands are for debugging only. If you must run one manually,
mirror the matching `Justfile` recipe, including `--override-input
themegen-cache ...` where applicable.

```sh
just themegen-generate framework
nix build .#nixosConfigurations.framework.config.system.build.toplevel --override-input themegen-cache path:$PWD/.cache/themegen/framework
sudo nixos-rebuild switch --flake .#framework --override-input themegen-cache path:$PWD/.cache/themegen/framework
```

The standalone Home Manager output `.#iceice666@framework` is kept only as a
legacy fallback while migration cleanup is pending. Do not use it for normal
Framework changes.

Fingerprint authentication is configured in
`hosts/framework/configuration/default.nix` through `services.fprintd.enable`
and `security.pam.services.{greetd,sudo}.fprintAuth`. Keep `fprintd` in the
Framework system packages so `fprintd-enroll` and related tools are available
for enrollment and troubleshooting.

Framework appearance scheduling is configured in `hosts/framework/home/gui.nix`
with Home Manager's `services.darkman`. It uses coarse Taipei coordinates from
the Framework timezone, exposes darkman through the XDG Settings portal, and
runs GTK/GNOME color-scheme scripts on sunrise/sunset transitions.

Framework Niri session persistence is configured through `services.nirinit` in
`hosts/framework/configuration/default.nix`. The upstream NixOS module installs
the `nirinit.service` user unit on `graphical-session.target`, so it starts with
the existing Niri session.

### Primary workflows

```sh
just build
just switch

just m3air-build
just m3air-rebuild
just framework-build
just framework-rebuild
just framework-boot

just fmt
just check
```

- `just build` auto-detects the current host and runs the matching dry build.
- `just switch` auto-detects the current host and applies the matching configuration.
- `just boot` auto-detects the current host and sets the Framework boot generation when supported.
- `just fmt` runs `nix fmt` through `treefmt-nix` (nixfmt + just formatters).
- `just check` runs `nix flake check --all-systems`.
- Explicit rebuild commands apply changes; prefer dry builds while iterating.

### Dry builds / targeted validation

There is no unit-test suite. The closest equivalent is the narrowest host build that covers the change.

```sh
just m3air-build
just framework-build
```

Which build to run for a given change:

| Changed path | Dry-build target(s) |
|---|---|
| `hosts/m3air/**` | `m3air` |
| `hosts/framework/home/**` | `framework` |
| `hosts/framework/configuration/**` | `framework` |
| `common/configuration/**` | `m3air` |
| `common/home/**` | `m3air` and `framework` |
| `pkgs/<name>` | dry-build any host that uses the package |

Overlay packages have no standalone `nix build` target; validate them through their host build.

### Other useful commands

```sh
just update
just update-input nixpkgs
just search <query>
just gc
just store-size
```

### Host-specific helpers

```sh
just m3air-homebrew    # install Homebrew (first-time macOS setup)
just m3air-activate    # reapply macOS settings without a full rebuild
just framework-bootstrap # install legacy Arch-owned Framework dependencies
just framework-build    # dry-build the Framework NixOS system
just framework-rebuild  # switch the Framework NixOS system
just framework-boot     # set the Framework NixOS system for next boot
```

### Secrets helpers

```sh
just secret-encrypt sensitive/hosts/m3air/forgejo.yaml ./forgejo.yaml
just secret-decrypt sensitive/hosts/m3air/forgejo.yaml
just secret-edit sensitive/hosts/m3air/forgejo.yaml
```

Never commit plaintext secrets. Keep secret material in `sensitive/shared/` encrypted with `sops`.

## Editor Rule Files

Checked locations:
- `.cursor/rules/`
- `.cursorrules`
- `.github/copilot-instructions.md`

None are present. `AGENTS.md` is the canonical instruction file in this repo.

## Documentation Scope

- Keep `README.md` concise and operator-facing.
- Keep detailed repo guidance in `AGENTS.md`.
- Put subsystem-specific detail close to the code, such as `common/home/themegen/README.md`.

## Code Style

### Formatting and whitespace

- Use 2 spaces for indentation; never use tabs.
- Keep one blank line between major top-level bindings in large attrsets.
- Keep closing `}` and `]` aligned with the opening expression.
- Run `just fmt` before finishing; formatting is enforced through `treefmt-nix`.

### Imports and module shape

- Returned attrsets start with `imports` when imports exist.
- Import shared modules with `(dotfiles + /path)`.
- Import directories by path, not by `/default.nix`.
- Keep host differences structural through separate files and explicit imports.
- Do not introduce `options`, `mkOption`, `mkEnableOption`, `mkIf`, or `mkMerge` unless explicitly requested.

Canonical module shape:

```nix
{ pkgs, dotfiles, ... }:
{
  imports = [ (dotfiles + /common/home) ./local-file.nix ];
  programs.foo.enable = true;
}
```

### Function arguments, `inherit`, and `let`

- Inline short argument sets: `{ pkgs, ... }:`.
- For 3 or more arguments, put one name per line and keep `...` last.
- Use inline `inherit` for 1-2 names; use vertical `inherit` blocks for 3+ names.
- Use `let` only for reused values or to name an otherwise opaque expression.

### Lists, attrs, and naming

- Keep short lists on one line; longer lists go one item per line.
- Align related assignments vertically when that improves readability.
- File names and package names use `kebab-case`.
- Nix attribute keys use upstream casing, usually `camelCase`.
- Preserve native external key casing like `NSGlobalDomain` and `AppleShowAllExtensions`.
- Fish function module names should match the function name.

### Types and data generation

- Prefer native Nix values over pre-serialized strings.
- Generate JSON config with `builtins.toJSON`.
- Generate attrsets from simple lists with `builtins.listToAttrs` plus `map`.
- Use `builtins.readDir` plus filtering when auto-importing `.nix` files from a directory.
- Limit `with pkgs;` to clear package-list contexts.

### Packages and overlays

- Register custom packages once in the overlay in `flake.nix`.
- New derivations live under `pkgs/<name>/default.nix`.
- Current overlay packages: `codex-cli-bin`, `default-browser`, `equibop-bin`, `rime-frost`, `rime-octagram-zh-hant-essay-bgw`, `themegen`, `utiluti`, `zed-bin`, `zen-bin`.
- Derivations should set `meta.mainProgram` and `meta.platforms`.
- Respect `runHook pre*` and `runHook post*` in custom phases.
- Use `lib.optionals` for platform-specific inputs.
- For platform-specific sources, follow the existing `srcs.${stdenvNoCC.hostPlatform.system} or (throw ...)` pattern.

### Error handling and safety

- Fail clearly for unsupported platforms with `throw`.
- Reference executables in activation scripts by Nix store path, not ambient `PATH`.
- Wire secrets through `config.sops.secrets.*.path` or `config.sops.placeholder.*`, not plaintext literals.
- When adding a secret, set `owner`, `group`, `mode`, and `restartUnits` deliberately.
- Keep comments sparse and useful; prefer short line comments.

## Repository Conventions

- `common/` is the baseline for all hosts.
- `common/configuration/` is only imported by `m3air` and is for Darwin system-level settings.
- `common/home/` is imported by all hosts and owns shared user packages.
- `themegen/` contains root-level plain templates split into `common/`, `m3air/`, and `framework/`; paths are `$HOME`-relative with no `home/` segment. `just themegen-generate <host>` renders concrete files into `.cache/themegen/<host>/` before builds, and Home Manager installs them through the `themegen-cache` flake input override.
- `common/home/rime/` copies Rime Frost data into the host Rime user directory, enables Traditional Chinese by default with `s2tw.json`, and installs the `zh-hant-t-essay-bgw` octagram model. macOS uses Squirrel from Homebrew; Linux uses Home Manager's Fcitx5 input method module with `fcitx5-rime`.
- `common/home/themegen/` supports wallpaper-driven theme generation. Template modules under `common/home/themegen/templates/` are auto-discovered, self-describe their rendered/copied outputs plus `home.file` targets, and include a VSCode theme module that installs a generated extension manifest into `.vscode-oss/extensions/`.
- `hosts/<name>/` contains machine-specific choices only.
- `framework` is NixOS with Home Manager imported into the system configuration.
- `hosts/framework/configuration/` is the active NixOS entrypoint; `hosts/framework/home/` contains user-level modules imported by it.
- `hosts/framework/home/eww/` runs the Framework Eww status bar; theme files come from `themegen/framework/.config/eww/`.
- `hosts/framework/home/niri-config.kdl` is the Framework Niri compositor config installed through Home Manager.
- `hosts/framework/configuration/default.nix` enables the upstream `nirinit` NixOS module for Niri session persistence.
- `hosts/framework/configuration/grub-theme.nix` builds the Framework GRUB theme from repo assets.
- `hosts/m3air/home/appearance.nix` builds and launches the macOS Swift appearance scheduler from `appearance-scheduler.swift`.
- `m3air/home/default-apps.nix` uses `default-browser` and `utiluti` to manage default browser and default editor associations on macOS.
- `sensitive/shared/` is for cross-host secrets.

## Change Strategy for Agents

- Make the smallest structural change that matches existing patterns.
- Prefer extending an existing host/common module over adding parallel abstractions.
- Keep `README.md` concise; put detailed operational guidance in `AGENTS.md` or focused sub-docs.
- Update docs when repo structure, commands, or host wiring changes.
- If a change affects runtime behavior, validate the narrowest relevant host or package build.
- For docs-only changes, a careful reread and consistency pass is usually enough.
- If you touch formatting-sensitive files, run `just fmt`.
- If you touch flake wiring or common modules, run `just check`.
