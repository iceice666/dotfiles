# AGENTS.md — Coding Agent Guide

This repository is a multi-host Nix dotfiles configuration managed with
[nix-darwin](https://github.com/nix-darwin/nix-darwin),
[home-manager](https://github.com/nix-community/home-manager), and
[just](https://github.com/casey/just).

---

## Repository Structure

```
flake.nix            # Flake entrypoint: all outputs (darwin/HM/NixOS)
Justfile             # Task runner (just)
common/              # Applied to every host
  configuration/     # Shared system-level packages
  home/              # Shared home-manager config (git, fish, starship, direnv)
    fish/            # Fish shell config + per-function .nix files
shared/              # Optional — imported by some but not all hosts
  home/              # e.g. zed.nix (desktop only), opencode.nix
hosts/               # Per-machine overrides
  m3air/             # macOS aarch64 (nix-darwin + home-manager)
  framework/         # Void Linux x86_64 (standalone home-manager)
  server/            # NixOS x86_64
pkgs/                # Custom derivations, added via overlay in flake.nix
```

Three-tier composition: `common/` (all hosts) → `shared/` (opt-in) → `hosts/<x>/` (machine-specific).

---

## Build / Apply Commands

All commands are run via `just` from the repo root.

| Recipe | Effect |
|---|---|
| `just m3air-rebuild` | `sudo darwin-rebuild switch --flake .#iceice666@m3air` |
| `just framework-rebuild` | `home-manager switch --flake .#iceice666@framework` |
| `just server-rebuild` | `sudo nixos-rebuild switch --flake .#homolab` |
| `just fmt` | Format all `.nix` files with `nixfmt` |
| `just check` | `nix flake check` — validates all flake outputs |
| `just update` | `nix flake update` — update all inputs |
| `just update-input <input>` | Update a single flake input, e.g. `just update-input nixpkgs` |
| `just gc` | `sudo nix-collect-garbage -d` |
| `just search <query>` | Search nixpkgs across `aarch64-darwin` and `x86_64-linux` |

### Validation (closest to "tests")

There are no unit tests. Use these to validate changes:

```sh
# Check the flake parses and all outputs evaluate without errors
just check

# Dry-run a specific host to see what would change without applying
sudo darwin-rebuild build --flake .#iceice666@m3air       # macOS
home-manager build --flake .#iceice666@framework           # framework
sudo nixos-rebuild build --flake .#homolab                 # server

# Format before committing
just fmt
```

For a single package derivation:
```sh
nix build .#packages.aarch64-darwin.equibop-bin
nix build .#packages.aarch64-darwin.aerospace-swipe
```

---

## Code Style

### Indentation & Whitespace

- **2 spaces** for all indentation — no tabs.
- One blank line between top-level attribute bindings in large attribute sets.
- Closing `}` or `]` at the same indent level as the opening line.

### Attribute Alignment (Columnar Style)

When multiple related assignments appear together, align values vertically:

```nix
home.username      = username;
home.homeDirectory = homeDirectory;

username      = "iceice666";
homeDirectory = "/Users/iceice666";
```

Use this pattern for `specialArgs`, `extraSpecialArgs`, and any group of
conceptually related bindings. Do not apply it globally — only where it
genuinely improves readability.

### Function Argument Lists

Short (1–2 args): inline.
```nix
{ pkgs, ... }:
{ username, homeDirectory, ... }:
```

Long (3+ args): one per line, trailing `...`, closing brace on its own line:
```nix
{
  pkgs,
  lib,
  inputs,
  username,
  homeDirectory,
  ...
}:
```

Stub modules that need no arguments: `{ ... }:`.

### `inherit` Style

Vertical form (preferred for 3+ names):
```nix
inherit
  inputs
  self
  username
  homeDirectory
  ;
```

Inline form for 1–2 names: `inherit pname version src;`

### `let`-`in` Blocks

Use only when a value is used more than once, or to name an otherwise-opaque expression.
`let` and the bindings are indented 2 spaces; `in` is at the outer level before `{`:

```nix
let
  pname   = "equibop-bin";
  version = "3.1.9";
in
stdenvNoCC.mkDerivation { ... }
```

### Lists

Short lists on one line: `imports = [ ./fish ./user.nix ];`

Longer lists — one item per line:
```nix
imports = [
  ../../../common/home
  ../../../shared/home/zed.nix
  ./aerospace.nix
];
```

### Comments

- `# Comment` on its own line above, or trailing on the same line.
- Use trailing comments for brief annotations: `"termius" # Linux-only in nixpkgs`.
- No block (`/* */`) comments in `.nix` files.
- Section banners (`# ── Title ───`) are reserved for the `Justfile`.

---

## Naming Conventions

| Thing | Convention | Examples |
|---|---|---|
| File names | `kebab-case.nix` | `system-defaults.nix`, `equibop-bin` |
| Directory names | `kebab-case` or single word | `m3air`, `aerospace-swipe`, `common`, `hosts` |
| Entry points | `default.nix` | every directory has one |
| Nix attribute keys | camelCase (follows upstream) | `shellAliases`, `extraPackages`, `stateVersion` |
| `pname` / overlay keys | `kebab-case` | `"equibop-bin"`, `"aerospace-swipe"` |
| Flake output keys | `user@host` or `hostname` | `"iceice666@m3air"`, `"homolab"` |
| Fish function files | match function name | `__expand_tilde_prefix.nix`, `mcd.nix` |

External config key names (macOS preferences, etc.) use their native casing
(`AppleShowAllExtensions`, `NSGlobalDomain`) — do not reformat these.

---

## Module Patterns

### Standard Module Shape

```nix
{ pkgs, lib, username, ... }:
{
  imports = [ ../../../common/home ./local-file.nix ];

  programs.foo.enable = true;
  programs.foo.settings = { ... };
}
```

- No custom `options` / `mkOption` / `mkEnableOption` — these are pure configuration modules.
- No `mkIf` / `mkMerge` — host differentiation is structural (separate files, explicit imports).
- `imports` always appears first in the returned attrset.
- Import directories by path without trailing `/default.nix`: `../../../common/home`.

### Overlay (adding custom packages)

Defined once in `flake.nix` and injected into every host:

```nix
let
  overlay = final: prev: {
    my-pkg = final.callPackage ./pkgs/my-pkg { };
  };
in {
  darwinConfigurations."..." = nix-darwin.lib.darwinSystem {
    modules = [ ... { nixpkgs.overlays = [ overlay ]; } ];
  };
  homeConfigurations."..." = home-manager.lib.homeManagerConfiguration {
    pkgs = nixpkgs.legacyPackages.x86_64-linux.extend overlay;
  };
}
```

### Custom Derivations (`pkgs/`)

```nix
{ lib, stdenv, fetchFromGitHub }:  # args one-per-line
stdenv.mkDerivation rec {           # use `rec` only when version is self-referenced
  pname   = "my-pkg";
  version = "1.2.3";
  src     = fetchFromGitHub { ... };
  buildPhase   = '' runHook preBuild  ... runHook postBuild  '';
  installPhase = '' runHook preInstall ... runHook postInstall '';
  meta = {
    description = "...";
    homepage    = "...";
    license     = lib.licenses.mit;
    mainProgram = "my-pkg";
    platforms   = lib.platforms.all;
  };
}
```

- Always respect `runHook pre*/post*` in phases.
- Use `lib.optionals` for conditional `nativeBuildInputs` / `buildInputs`.
- Use `srcs.${stdenvNoCC.hostPlatform.system} or (throw "unsupported: ${...}")` for multi-platform binaries.
- Always provide `meta.mainProgram` and `meta.platforms`.

### Auto-Import Pattern (fish functions)

```nix
imports = map (f: ./functions/${f})
  (builtins.filter (f: builtins.match ".*\\.nix" f != null)
    (builtins.attrNames (builtins.readDir ./functions)));
```

Use `builtins.readDir` + `builtins.filter` to auto-discover `.nix` files in a
directory rather than maintaining a manual list.

### Generating Config Files in Nix

Prefer `builtins.toJSON` for JSON-format configs to keep everything in Nix:

```nix
home.file.".config/app/config.json".text = builtins.toJSON {
  key = "value";
};
```

Use `builtins.listToAttrs` + `map` to turn a simple name list into a
`{ name = true; }` attribute set:

```nix
extensions = builtins.listToAttrs (map (name: { inherit name; value = true; }) [
  "nix" "ocaml" "dockerfile"
]);
```

### home-manager Activation Scripts

```nix
home.activation.myScript = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  if [ ! -d "${homeDirectory}/.something" ]; then
    ${pkgs.git}/bin/git clone https://... "${homeDirectory}/.something"
  fi
'';
```

Reference executables by Nix store path (`${pkgs.git}/bin/git`) — never rely on ambient `PATH`.

---

## Adding a New Host

1. Create `hosts/<hostname>/configuration/default.nix` (system config, if applicable).
2. Create `hosts/<hostname>/home/default.nix`; start with `imports = [ ../../../common/home ];`.
3. Add the flake output in `flake.nix` following the `user@host` naming pattern.
4. Pass `username`, `homeDirectory`, `inputs`, and `self` via `specialArgs` / `extraSpecialArgs`.
5. Run `just check` to validate, then apply with the appropriate rebuild recipe.

## Adding a New Package

1. Create `pkgs/<pname>/default.nix` as a standard derivation.
2. Register it in the `overlay` in `flake.nix`.
3. Reference it by name in `home.packages` or `environment.systemPackages` where needed.
