# AGENTS.md - Repository Guide

This repository is a multi-host Nix dotfiles setup built around `flake.nix`, `nix-darwin`, `home-manager`, `sops-nix`, `treefmt-nix`, and `just`.
Use this file as the working agreement for coding agents editing this repo.

`README.md` is the concise operator-facing overview. Keep the detailed implementation and editing guidance here.

## Repository Shape
```text
flake.nix            # all flake inputs and outputs
Justfile             # rebuild, validation, secrets, maintenance workflows
treefmt.nix          # formatter configuration
assets/              # wallpaper/source images used by theme generation

common/              # baseline shared across hosts
  configuration/     # shared system-level modules and packages for darwin/NixOS hosts
  home/              # shared Home Manager baseline
    fish/            # fish config + auto-imported function modules
    opencode/        # shared opencode config and skill wiring

shared/              # optional modules used by some hosts
  home/              # reusable Home Manager modules
    ghostty.nix      # shared Ghostty config
    themegen/        # wallpaper-driven theme generation and templates
    vscodium.nix     # VSCodium config + marketplace wiring
    zed.nix          # Zed config

hosts/               # per-host entrypoints
  m3air/             # macOS via nix-darwin
  framework/         # standalone Home Manager on Linux
    configuration/   # placeholder directory, not wired into the flake today
    home/            # active Home Manager entrypoint
  server/            # NixOS host named homolab
    configuration/   # active NixOS entrypoint
    home/            # Home Manager modules for the server user

pkgs/                # overlay packages: default-browser, equibop-bin, mise-bin, themegen, utiluti
sensitive/           # encrypted secret and certificate material managed by sops
  shared/            # cross-host secrets, currently OpenRouter credentials
  hosts/server/      # server-only secrets and certificates
```
Composition is structural: `common/ -> shared/ -> hosts/<name>/`.

Flake outputs:
- `darwinConfigurations."iceice666@m3air"`
- `homeConfigurations."iceice666@framework"`
- `nixosConfigurations."homolab"`

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
just server-build
just server-rebuild

just fmt
just check
```
- `just build` auto-detects the current host and runs the matching dry build.
- `just switch` auto-detects the current host and applies the matching configuration.
- `just server-build` and `just server-rebuild` refuse to run on non-server hosts.
- `just fmt` runs `nix fmt` through `treefmt-nix`.
- `just check` runs `nix flake check --all-systems`.
- Explicit rebuild commands apply changes; prefer dry builds while iterating.

### Dry builds / targeted validation
There is no unit-test suite here. The closest equivalent to a test is the narrowest host or package build that covers your change.
```sh
sudo darwin-rebuild build --flake .#iceice666@m3air
home-manager build --flake .#iceice666@framework
sudo nixos-rebuild build --flake .#homolab

nix build .#packages.aarch64-darwin.equibop-bin
```
- `hosts/m3air/**` -> dry-build `m3air`.
- `hosts/framework/home/**` -> dry-build `framework`.
- `hosts/framework/configuration/**` -> placeholder only; there is no active flake target there today.
- `hosts/server/**` -> dry-build `homolab`.
- `common/configuration/**` -> dry-build `m3air` and `homolab`.
- `common/home/**` -> build each consuming host: `m3air`, `framework`, and `homolab`.
- `shared/home/**` -> build each importing host, currently `m3air` and `framework`.
- `pkgs/<name>` -> build that package directly; if it is wired into a host, also dry-build the affected host when practical.

### Single-test guidance
- There is no per-test runner.
- For a "single test", run the smallest build that covers the change.
- One host change -> build only that host.
- One package change -> `nix build .#packages.<system>.<name>`.
- One file formatting check -> run `nixfmt path/to/file.nix` if available, then `just fmt` before finishing.

### Other useful commands
`just update`, `just update-input nixpkgs`, `just search zed`, `just gc`, `just store-size`

### Host-specific helpers
```sh
just m3air-homebrew
just m3air-activate
just server-gen-hardware
```
- `just m3air-homebrew` installs Homebrew during first-time macOS setup.
- `just m3air-activate` reapplies macOS settings without a full rebuild.
- `just server-gen-hardware` must be run on the server and rewrites `hosts/server/configuration/hardware-configuration.nix`.

### Secrets helpers
```sh
just secret-encrypt sensitive/hosts/server/forgejo.yaml ./forgejo.yaml
just secret-decrypt sensitive/hosts/server/forgejo.yaml
just secret-decrypt sensitive/hosts/server/cloudflared-token.key /tmp/cloudflared-token
```
Never commit plaintext secrets. Keep secret material in `sensitive/shared/` or `sensitive/hosts/server/` encrypted with `sops`.

## Editor Rule Files
Checked locations:
- `.cursor/rules/`
- `.cursorrules`
- `.github/copilot-instructions.md`
No repository-local Cursor or Copilot instruction files are present, so this `AGENTS.md` is the canonical instruction file in the repo.

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
- Current overlay packages are `default-browser`, `equibop-bin`, `mise-bin`, `themegen`, and `utiluti`.
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
- `common/configuration/` is only imported by `m3air` and `homolab`.
- `common/home/` is imported by all three hosts.
- `common/home/opencode/` uses `sensitive/shared/openrouter.yaml`.
- `shared/` is opt-in and should stay reusable across hosts.
- `shared/home/themegen/` supports wallpaper-driven theme generation for hosts that import `shared/home/themegen/default.nix`.
- `hosts/<name>/` contains machine-specific choices only.
- `framework` is standalone Home Manager and warns about packages that cannot come from `environment.systemPackages`.
- `hosts/framework/home/` is the active flake entrypoint; `hosts/framework/configuration/` is currently just a placeholder directory.
- `hosts/server/configuration/services/dynacat.nix` is the dashboard service; do not refer to it as Homepage.
- `hosts/server/configuration/hardware-configuration.nix` is machine-specific and should only be regenerated on the target server.
- `m3air/home/default-apps.nix` uses `default-browser` and `utiluti` to manage default browser and default editor associations on macOS.
- `sensitive/shared/` is for cross-host secrets; `sensitive/hosts/server/` is for server-only material.

## Change Strategy for Agents
- Make the smallest structural change that matches existing patterns.
- Prefer extending an existing host/shared/common module over adding parallel abstractions.
- Keep `README.md` concise; put detailed operational guidance in `AGENTS.md` or focused sub-docs.
- Update docs when repo structure, commands, or host wiring changes.
- If a change affects runtime behavior, validate the narrowest relevant host or package build.
- For docs-only changes, a careful reread and consistency pass is usually enough.
- If you touch formatting-sensitive files, run `just fmt`.
- If you touch flake wiring or shared modules, run `just check`.
