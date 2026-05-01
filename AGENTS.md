# AGENTS.md - Repository Guide

This repository is a multi-host Nix dotfiles setup built around `flake.nix`, `nix-darwin`, `home-manager`, `sops-nix`, `treefmt-nix`, and `just`.
Use this file as the working agreement for coding agents editing this repo.

`README.md` is the concise operator-facing overview. Keep the detailed implementation and editing guidance here.

## Repository Shape

```text
flake.nix            # all flake inputs and outputs
Justfile             # rebuild, validation, secrets, maintenance workflows
treefmt.nix          # formatter configuration (nixfmt + just)
assets/              # wallpaper/source images used by theme generation

common/              # baseline shared across all hosts
  configuration/     # shared system-level modules and packages for darwin hosts
    default.nix      # imports packages.nix; adds unstable codex, agent-browser, cascadia-code font
    packages.nix     # stable system package list
  home/              # shared Home Manager baseline (imported by all hosts)
    default.nix
    user.nix
    fish/            # fish config + auto-imported function modules (13 functions)
    opencode/        # opencode config with OpenRouter secret + skill-creator skill

shared/              # optional modules used by some hosts
  home/              # reusable Home Manager modules
    ghostty.nix      # shared Ghostty config
    themegen/        # wallpaper-driven theme generation and templates
      templates/     # ghostty, equibop, opencode, starship, zed, vscode, terminal-sequences
    vscodium.nix     # VSCodium config + marketplace wiring
    zed.nix          # Zed config

hosts/               # per-host entrypoints
  m3air/             # macOS via nix-darwin
    configuration/   # default.nix, system-defaults.nix
    home/            # default.nix, default-apps.nix, karabiner.nix, wallpaper.nix
  framework/         # standalone Home Manager on Void Linux
    configuration/   # placeholder directory, not wired into the flake today
    home/            # active Home Manager entrypoint

pkgs/                # overlay packages
  default-browser/   # macOS default browser helper
  equibop-bin/       # Equibop binary
  mise-bin/          # mise binary
  themegen/          # Rust-based theme generator (Cargo project)
  utiluti/           # macOS utility for default app associations
  zed-bin/           # Zed official prebuilt releases
  youtube-rss-proxy/ # EMPTY - not wired into the overlay or any host

sensitive/           # encrypted secret and certificate material managed by sops
  shared/            # cross-host secrets: openrouter.yaml
```

Composition is structural: `common/ -> shared/ -> hosts/<name>/`.

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
`self.submodules = true` is set so Git submodules are fetched.

### Outputs

| Output | Type |
|---|---|
| `darwinConfigurations."iceice666@m3air"` | nix-darwin configuration |
| `homeConfigurations."iceice666@framework"` | standalone Home Manager configuration |
| `formatter.aarch64-darwin` / `formatter.x86_64-linux` | treefmt |

There are **no `packages.*` outputs** in the flake. Overlay packages are only accessible through host configurations, not as standalone flake outputs.

### Overlay

Custom packages registered in the overlay: `default-browser`, `equibop-bin`, `mise-bin`, `themegen`, `utiluti`, `zed-bin`.

Additionally, `direnv` is overridden to strip `-linkmode=external` from its Makefile (build fix).

### `unstablePkgsFor`

A helper is defined that imports `nixpkgs-unstable` with `allowUnfree = true` and `cudaSupport = true`, with the overlay applied. Used to pull in `codex`, `agent-browser`, and `sops` from unstable.

## Build, Format, and Validation Commands

Run commands from the repository root.

### Primary workflows

```sh
just build
just switch

just m3air-build
just m3air-rebuild
just framework-build
just framework-rebuild

just fmt
just check
```

- `just build` auto-detects the current host and runs the matching dry build.
- `just switch` auto-detects the current host and applies the matching configuration.
- `just fmt` runs `nix fmt` through `treefmt-nix` (nixfmt + just formatters).
- `just check` runs `nix flake check --all-systems`.
- Explicit rebuild commands apply changes; prefer dry builds while iterating.

### Dry builds / targeted validation

There is no unit-test suite. The closest equivalent is the narrowest host build that covers the change.

```sh
sudo darwin-rebuild build --flake .#iceice666@m3air
home-manager build --flake .#iceice666@framework
```

Which build to run for a given change:

| Changed path | Dry-build target(s) |
|---|---|
| `hosts/m3air/**` | `m3air` |
| `hosts/framework/home/**` | `framework` |
| `hosts/framework/configuration/**` | placeholder only; no active flake target |
| `common/configuration/**` | `m3air` |
| `common/home/**` | `m3air` and `framework` |
| `shared/home/**` | `m3air` and `framework` (current importers) |
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
- Put subsystem-specific detail close to the code, such as `shared/home/themegen/README.md`.

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
- Current overlay packages: `default-browser`, `equibop-bin`, `mise-bin`, `themegen`, `utiluti`, `zed-bin`.
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
- `common/configuration/` is only imported by `m3air`.
- `common/home/` is imported by all hosts.
- `common/home/opencode/` uses `sensitive/shared/openrouter.yaml`.
- `shared/` is opt-in and should stay reusable across hosts.
- `shared/home/themegen/` supports wallpaper-driven theme generation. Template modules under `shared/home/themegen/templates/` are auto-discovered, self-describe their rendered/copied outputs plus `home.file` targets, and include a VSCode theme module that installs a generated extension manifest into `.vscode-oss/extensions/`.
- `hosts/<name>/` contains machine-specific choices only.
- `framework` is standalone Home Manager on Void Linux. It warns about packages from `common/configuration/packages.nix` that cannot come from `environment.systemPackages`.
- `hosts/framework/home/` is the active flake entrypoint; `hosts/framework/configuration/` is a placeholder directory with no active flake target.
- `m3air/home/default-apps.nix` uses `default-browser` and `utiluti` to manage default browser and default editor associations on macOS.
- `sensitive/shared/` is for cross-host secrets.
- `pkgs/youtube-rss-proxy/` is an empty directory that is not wired into the overlay or any host; do not reference it as an available package.

## Change Strategy for Agents

- Make the smallest structural change that matches existing patterns.
- Prefer extending an existing host/shared/common module over adding parallel abstractions.
- Keep `README.md` concise; put detailed operational guidance in `AGENTS.md` or focused sub-docs.
- Update docs when repo structure, commands, or host wiring changes.
- If a change affects runtime behavior, validate the narrowest relevant host or package build.
- For docs-only changes, a careful reread and consistency pass is usually enough.
- If you touch formatting-sensitive files, run `just fmt`.
- If you touch flake wiring or shared modules, run `just check`.
