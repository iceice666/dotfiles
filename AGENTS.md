# AGENTS.md - Repository Guide

This repository is a multi-host Nix dotfiles setup built around `flake.nix`, `nix-darwin`, `home-manager`, `sops-nix`, `treefmt-nix`, and `just`.
Use this file as the working agreement for coding agents editing this repo.

`README.md` is the concise operator-facing overview. Keep the detailed implementation and editing guidance here.

## Repository Shape

```text
flake.nix            # flake inputs and thin local framework entrypoint
Justfile             # thin task runner for build, switch, validation, secrets, maintenance
scripts/             # shell implementations for complex just recipes
treefmt.nix          # formatter configuration (nixfmt + just)
assets/              # wallpaper/source images and host avatar assets

common/              # shared modules injected by mk-host into every host
  system/            # always-on: Lix, cascadia-code font, fish, allowUnfree
  system-darwin/     # darwin-only system settings (experimental-features)
  system-nixos/      # nixos-only system settings (experimental-features)
  home-base/         # CLI baseline for all HM-enabled hosts
    default.nix      # git, direnv, neovim, zoxide, starship, sops-age, zellij config
    packages-cli.nix # shared CLI package list
    user.nix
    fish/            # fish config + auto-imported function modules (12 functions)
    agent-skills.nix # shared agent-agnostic personal skills
    claude.nix       # Claude Code config symlinks
    dev-env.nix      # developer environment PATH/ENV (features.devEnv)
    pi.nix           # Pi coding-agent ketch extension (features.pi)
  home-gui/          # GUI workstation baseline (features.gui)
    default.nix      # imports app-defaults, ghostty, packages-gui, vscodium, zed
    packages-gui.nix # GUI binaries: claude-code-bin, equibop-bin, zen-bin, …
    app-defaults.nix # XDG MIME associations
    ghostty.nix      # Ghostty config
    vscodium.nix     # VSCodium config + marketplace wiring
    zed.nix          # Zed config
    rime/            # Rime Frost setup with Traditional Chinese octagram model (features.rime)
    themegen/        # wallpaper-driven theme generation (features.themegen)

themegen/            # root-level plain theme templates, split by common/host
  common/            # shared $HOME-relative templates for shells/editors/terminal
  m3air/             # macOS-only $HOME-relative templates
  framework/         # Linux-only $HOME-relative templates for GTK/Qt/fuzzel/Eww
  preview.html       # HTML palette preview template

hosts/               # per-host entrypoints
  m3air/             # macOS via nix-darwin
    host.nix         # feature manifest
    configuration/   # default.nix, system-defaults.nix
    home/            # appearance, default-apps, karabiner, wallpaper, _module.args
    wallpaper.jpg    # symlink → assets/win_chan.jpg
  framework/         # NixOS system with Home Manager
    host.nix         # feature manifest
    overlay.nix      # framework-only kernel pin (linux_zen_7_0)
    configuration/   # active NixOS system entrypoint, hardware, GRUB theme
    home/            # GUI/Niri/Eww Home Manager modules
    wallpaper.png    # symlink → assets/mzen.png
  homolab/           # NixOS server (x86_64), AI/GPU plane — deployed from m3air over SSH
    host.nix         # feature manifest
    configuration/   # system.nix, networking.nix, sensitive/, user.nix, hardware-configuration.nix
    services/        # edge/ (Traefik, Authelia, Cloudflare, SSH, Tailscale, node-exporter), ai/ (llama-swap, OmniRoute)
    home/            # homolab-specific home additions (fish-pj.nix, user.nix, mise)
    apps/            # repo-local applications (e.g. daily-audit)
    patches/         # nixpkgs patches to apply at build time
    plan/            # design notes for in-flight homolab work
  lumo/              # Alpine 3.24 server (aarch64, Raspberry Pi 5), data+apps plane
    host.nix         # standalone root Home Manager + deploy-rs metadata
    home/services/   # Nix binaries, generated configs, OpenRC activation
  gateway/           # Alpine 3.24 edge appliance (aarch64, Raspberry Pi 5)
    host.nix         # standalone root Home Manager + deploy-rs metadata
    home/            # shared CLI baseline; host services are bootstrapped through Alpine
  gce-dns/           # Google Compute Engine NixOS image host for Blocky DoH
    host.nix         # feature manifest
    configuration/   # GCE image, Blocky DoH, Tailscale metadata bootstrap, local deploy user

lib/                 # shared nix helpers and local flake framework
  flake/             # auto-discovery, mk-host, home-manager wiring, overlays/, deploy, formatter, devshell outputs
  homolab.nix        # hostnames, ports, domains, IP ranges for homolab

pkgs/                # overlay packages
  blocky-bin/        # official prebuilt Blocky DNS proxy releases
  claude-code-bin/   # official prebuilt Anthropic Claude Code CLI releases
  codex-cli-bin/     # official prebuilt OpenAI Codex CLI releases
  default-browser/   # macOS default browser helper
  equibop-bin/       # Equibop binary
  framework-eww-state/ # Rust state daemon/action helper for Framework Eww
  kaguya-bin/        # Framework Kaguya browser binary wrapper fed by kaguya-cache
  ketch/             # web/code/docs search and scraping CLI for Pi tools
  pi-coding-agent-bin/ # official prebuilt Pi Coding Agent releases
  rime-frost/        # Rime Frost schema data
  rime-octagram-zh-hant-essay-bgw/ # Traditional Chinese octagram grammar model
  themegen/          # Rust-based theme generator (Cargo project)
  utiluti/           # macOS utility for default app associations
  zed-bin/           # Zed official prebuilt releases
  zen-bin/           # Zen Browser Darwin package

sensitive/           # encrypted secret and certificate material managed by sops
  shared/            # cross-host secrets
```

Host outputs are **auto-discovered**: `lib/flake/hosts.nix` scans `hosts/*/host.nix` at
evaluation time — no hand-maintained list. Per-host specs declare a `features` attrset;
`lib/flake/mk-host.nix` injects matching `common/` modules and wires Home Manager.

## Flake Details

### Inputs

| Input | Source | Follows nixpkgs |
|---|---|---|
| `nixpkgs` | `github:NixOS/nixpkgs/nixos-26.05` | — |
| `nixpkgs-unstable` | `github:NixOS/nixpkgs/nixpkgs-unstable` | no |
| `nix-darwin` | `github:nix-darwin/nix-darwin/nix-darwin-26.05` | yes |
| `home-manager` | `github:nix-community/home-manager/release-26.05` | yes |
| `treefmt-nix` | `github:numtide/treefmt-nix` | yes |
| `sops-nix` | `github:Mic92/sops-nix` | yes |
| `deploy-rs` | `github:serokell/deploy-rs` | yes |
| `nirinit` | `github:amaanq/nirinit` | yes |
| `reimu-on-starlit-water` | `path:/home/iceice666/code/reimu_lays_on_water` | no |
| `kaguya-cache` | `git+file:.?dir=pkgs/kaguya-bin/empty-cache` | no |
| `kaguya-browser` | `git+file:.?dir=pkgs/kaguya-bin` | yes |
| `zen-browser` | `github:youwen5/zen-browser-flake` | yes |
`self.submodules = true` is set so Git submodules are fetched.

Theme files are generated by `common/home-gui/themegen/default.nix` as host-specific
Nix derivations from each host wallpaper plus `themegen/common/` and
`themegen/<host>/` templates.

`kaguya-browser` is the local flake under `pkgs/kaguya-bin` that exposes the
Framework-only Kaguya browser package. Its `kaguya-cache` input is a placeholder
for the copied binary runtime. Linux build, boot, and switch recipes ensure
`.cache/kaguya/framework` exists, fetching from homolab only when missing or
invalid, then replace the root `kaguya-cache` input in-memory with
`path:$PWD/.cache/kaguya/framework`. Run `just kaguya` to force-refresh the
cache.

### Outputs

| Output | Type |
|---|---|
| `darwinConfigurations.m3air` | nix-darwin configuration |
| `nixosConfigurations.framework` | NixOS configuration |
| `nixosConfigurations.homolab` | NixOS server configuration (deployed via SSH) |
| `homeConfigurations.lumo` | Alpine root Home Manager data+apps configuration |
| `homeConfigurations.gateway` | Alpine root Home Manager edge configuration |
| `nixosConfigurations.gce-dns` | NixOS Google Compute Engine image host |
| `deploy` | deploy-rs node definitions for `framework`, `homolab`, `lumo`, `gateway`, and `gce-dns` |
| `checks.x86_64-linux` | deploy-rs schema validation checks |
| `devShells.aarch64-darwin.default` / `devShells.x86_64-linux.default` | Rust/themegen development shell (includes `deploy`) |
| `formatter.aarch64-darwin` / `formatter.x86_64-linux` | treefmt |
| `packages.<system>.*` | standalone overlay packages (themegen, ketch, claude-code-bin, …) |

Standalone packages are available for all systems: `nix build .#themegen` works without going through a host build.

### Local flake framework

`flake.nix` only declares inputs and imports `lib/flake`. Framework files are
split by output responsibility:

- `lib/flake/hosts.nix` **auto-discovers** `hosts/*/host.nix` via `builtins.readDir` — no hand-maintained list.
- `lib/flake/mk-host.nix` builds `nixosSystem`, `darwinSystem`, or standalone `homeManagerConfiguration` outputs. It reads `host.features` to inject the matching shared modules.
- `lib/flake/home-manager.nix` generates the `home-manager = { … };` module from host features and home imports — no per-host duplication.
- `lib/flake/overlays/` registers custom packages split by purpose: `lix.nix`, `binaries.nix`, `linux-gui.nix` (Linux-only, no throw on Darwin), `global-patches.nix`.
- `lib/flake/pkgs.nix` defines `unstablePkgsFor`.
- `lib/flake/systems.nix` is the single source of truth for the supported system list.
- `lib/flake/deploy.nix` generates deploy-rs nodes from host deploy metadata.
- `lib/flake/dev-shells.nix` and `lib/flake/formatters.nix` consume `systems.nix`.

Host specs own: `name`, `kind`, `system`, `username`, `homeDirectory`, optional `modules`, `homeModules`, `features`, `extraSpecialArgs`, and optional `deploy`. `kind` may be `nixos`, `darwin`, or `home-manager`.

| Feature flag | What it injects |
|---|---|
| `homeManager` | system-module Home Manager wiring for NixOS/nix-darwin |
| `sops` | system sops module plus HM sharing, or standalone HM sops module |
| `gui` | `common/home-gui` |
| `themegen` | `common/home-gui/themegen` |
| `rime` | `common/home-gui/rime` |
| `devEnv` | `common/home-base/dev-env.nix` |
| `pi` | `common/home-base/pi.nix` |
| `nirinit` | `inputs.nirinit.nixosModules.nirinit` |
| `kaguya` | (signals framework-local overlay; no module) |

**Adding a host:** create `hosts/<new>/host.nix` with `{ inputs, dotfiles, name }:` signature, declare `features`, and add `homeModules = [ ./home ]`. The host appears as a flake output automatically.

### Overlay

The overlay is split into four focused files under `lib/flake/overlays/`:

- `lix.nix` — inherits `nix-eval-jobs`, `nix-fast-build`, `nixpkgs-review` from `pkgs.lixPackageSets.stable`.
- `binaries.nix` — binary and cross-platform packages: `blocky-bin`, `claude-code-bin`, `codex-cli-bin`, `default-browser`, `equibop-bin`, `framework-eww-state`, `ketch`, `pi-coding-agent-bin`, `rime-frost`, `rime-octagram-zh-hant-essay-bgw`, `themegen`, `utiluti`, `zed-bin`, `zen-bin`.
- `linux-gui.nix` — Linux-only packages: `kaguya-bin`, `niri-scratchpad-helper`, `reimu-on-starlit-water`, `eww` transparency patch. Attributes are omitted (not thrown) on non-Linux.
- `global-patches.nix` — `direnv` build fix (strips `-linkmode=external` from Makefile).

The Framework-only kernel pin (`linux_zen_7_0`, `linuxPackages_zen_7_0`) lives in
`hosts/framework/overlay.nix` and is applied locally via `nixpkgs.overlays` in the
Framework system configuration — not in the shared overlay.

Additional notes:
- `reimu-on-starlit-water` imports the local package expression from `/home/iceice666/code/reimu_lays_on_water/nix/package.nix` through a non-flake path input and builds it with the `nixpkgs-unstable` Rust toolchain.
- `zen-bin` uses the `zen-browser` flake on Linux and the local Darwin package under `pkgs/zen-bin`.

### `unstablePkgsFor`

A helper is defined that imports `nixpkgs-unstable` with `allowUnfree = true` and `cudaSupport = true`, with the overlay applied. Used by shared Home Manager modules to pull in `bun` and `sops` from unstable.

## Web, Code, and Docs Research

Pi is configured through `common/home-base/pi.nix` to install `ketch` and expose these Pi tools: `ketch_search`, `ketch_scrape`, `ketch_code`, and `ketch_docs`.
Use them for external web research, URL fetching, OSS code examples, and library docs when repository-local information is insufficient.

## Build, Format, and Validation Commands

Run commands from the repository root.

## Framework NixOS Setup

`framework` is a NixOS machine managed by the `nixosConfigurations.framework`
flake output. The system imports `home-manager.nixosModules.home-manager`, so
Framework user configuration still lives under `hosts/framework/home/`, but the
active switch path is the NixOS system target.

Build and activate the Framework system:

```sh
just build
just switch
```

Prefer these `just` recipes over direct `nix build`, `darwin-rebuild`,
`nixos-rebuild`, or `home-manager` commands. The recipes run required
pre-build steps such as the Kaguya cache ensure on Linux and pass the correct
flake input overrides.

Direct `deploy` commands are for debugging only. If you must run one manually,
mirror the matching `Justfile` recipe, including the Kaguya cache override.

```sh
./scripts/kaguya-cache ensure
deploy .#framework --dry-activate -- --override-input kaguya-cache path:$PWD/.cache/kaguya/framework
deploy .#framework -- --override-input kaguya-cache path:$PWD/.cache/kaguya/framework
```

Fingerprint authentication is configured in
`hosts/framework/configuration/default.nix` through `services.fprintd.enable`
and `security.pam.services.{greetd,sudo}.fprintAuth`. Keep `fprintd` in the
Framework system packages so `fprintd-enroll` and related tools are available
for enrollment and troubleshooting.

Framework appearance scheduling is configured in `hosts/framework/home/gui.nix`
with Home Manager's `services.darkman`. It uses coarse Taipei coordinates from
the Framework timezone, exposes darkman through the XDG Settings portal, and
runs GTK/GNOME color-scheme scripts on sunrise/sunset transitions.

Framework Niri session persistence is configured through `services.nirinit`. The
`nirinit` NixOS module is injected via `features.nirinit = true` in
`hosts/framework/host.nix`. It installs the `nirinit.service` user unit on
`graphical-session.target`, so it starts with the existing Niri session.

### Primary workflows

```sh
just build
just switch
just boot

just theme
just kaguya
just theme-preview
just fmt
just fmt-check
just check
```

- `just build` and `just switch` are platform-gated duplicate recipes: macOS maps to `m3air`, and Linux maps to `framework`.
- `just boot` is Linux-only and sets the Framework NixOS generation for next boot.
- Theme files are generated inside the host build by a Nix derivation.
- `just theme` generates a local concrete theme cache for inspection only.
- Framework build, switch, and boot recipes reuse `.cache/kaguya/framework` and
  fetch Kaguya only when missing or invalid.
- `just kaguya` force-refreshes the Framework Kaguya runtime cache.
- `just fmt` runs `nix fmt` through `treefmt-nix` (nixfmt + just formatters).
- `just check` runs format, Justfile metadata, and `nix flake check --all-systems`.
- Recipe groups and platform guards use official `just` attributes such as `[group('host')]`, `[macos]`, and `[linux]`.

### Dry builds / targeted validation

There is no unit-test suite. The closest equivalent is the narrowest host build that covers the change.

```sh
just build
```

Run it on the platform that owns the changed host. For shared changes, dry-build
on both `m3air` and `framework`.

Which build to run for a given change:

| Changed path | Dry-build target(s) |
|---|---|
| `hosts/m3air/**` | `m3air` |
| `hosts/framework/home/**` | `framework` |
| `hosts/framework/configuration/**` | `framework` |
| `hosts/homolab/**` | `homolab` (via `just homolab-build`) |
| `hosts/lumo/**` | `lumo` (via `just lumo-build`) |
| `hosts/gateway/**` | `gateway` (via `just gateway-build`) |
| `hosts/gce-dns/**` | `gce-dns` (via `just gce-dns-build`; image changes via `just gce-dns-image`) |
| `lib/homolab.nix` | `homolab` + `lumo` + `gateway` |
| `common/system/**` | `m3air` + `framework` + `homolab` + `gce-dns` |
| `common/system-darwin/**` | `m3air` |
| `common/system-nixos/**` | `framework` + `homolab` + `gce-dns` |
| `common/home-base/**` | all Home Manager-enabled hosts |
| `common/home-alpine/**` | `lumo` + `gateway` |
| `common/home-gui/**` | `m3air` + `framework` |
| `pkgs/<name>` | `nix build .#<name>` (standalone) or any host that uses it |

### Other useful commands

```sh
just update
just update nixpkgs
just search <query>
just gc
just store-size
```

### Host-specific helpers

```sh
just m3air-homebrew    # install Homebrew (first-time macOS setup)
just m3air-activate    # reapply macOS settings without a full rebuild

just homolab-build           # dry-activate homolab on the server itself
just homolab-switch          # build + activate homolab via SSH
just homolab-boot            # stage the closure for next homolab boot
just homolab-gen-hardware    # refresh hardware-configuration.nix from the live server
just homolab-llama-smoke     # OpenAI-compatible smoke check against the homolab LLM stack

just gce-dns-build           # dry-build the gce-dns NixOS system toplevel
just gce-dns-image           # build the gce-dns Google Compute Engine image
just gce-dns-switch          # deploy gce-dns over Tailscale after first boot

just gateway-bootstrap       # prepare an official Alpine 3.24 gateway installation
just gateway-build           # dry-activate gateway root Home Manager
just gateway-switch          # deploy gateway root Home Manager

just lumo-bootstrap          # converge the existing Alpine 3.24 lumo installation
just lumo-build              # dry-activate lumo root Home Manager
just lumo-switch             # deploy lumo root Home Manager
just lumo-smoke              # verify lumo OpenRC services and local endpoints
```

Homolab is deployed via deploy-rs with `remoteBuild = true`, so the build runs on
the server itself over SSH and avoids cross-compilation. The deploy user must have
passwordless sudo for the deploy-rs activation script.

`lumo` and `gateway` run Alpine Linux 3.24 with root-only Lix installed using
`--init none`. deploy-rs activates standalone root Home Manager profiles and
builds each aarch64 closure on its target. Alpine/APK owns boot, the kernel,
networking, OpenSSH, Tailscale, cgroups, and the nftables launcher. Home Manager
owns root tooling and Nix-provided application services supervised by OpenRC.

`lumo` is the data+apps plane: Postgres, Valkey, git-server, Podman, Prometheus,
Grafana, Dynacat, dev-port-proxy, and the daily audit. Traefik on `homolab`
proxies Grafana/Dynacat/dev-port-proxy to `lumo`'s LAN IP (`192.168.1.128`).
Inter-host metrics scraping (Prometheus on lumo
→ node-exporter/traefik-metrics on homolab) goes over the tailnet. Grafana's
`auth.proxy.whitelist` is set to `homolab`'s LAN IP — never widen this without
adjusting the firewall rule that scopes the Grafana port to `homolab` only.

After provisioning either Alpine board:
1. Run `just <host>-bootstrap`; it installs host primitives and prints the age recipient.
2. Add the recipient anchor and host rule entry to `.sops.yaml`.
3. Re-encrypt host secrets with `just secret-refresh sensitive/hosts/<host>`.
4. Run `just <host>-build`, then `just <host>-switch`.
5. Reboot and run `just lumo-smoke` for lumo.

`gce-dns` is a GCE image host for Blocky DoH. Blocky serves `/dns-query` and
Prometheus metrics on TCP port 4000 over Tailscale; classic UDP DNS is not
opened. First boot expects a GCE instance metadata attribute named
`tailscale-auth-key`, containing a preauthorized Tailscale auth key. The host
joins as `gce-dns`, enables Tailscale SSH, keeps public OpenSSH disabled, and
disables Google OS Login. Build the image on `x86_64-linux` or through an
available Linux builder.

### Homolab-specific danger areas

Touch these with care; misconfiguration affects the server's reachability or
trust boundary:

- `hosts/homolab/configuration/networking.nix` — firewall, iptables, SSH exposure.
- `lib/homolab.nix` — hostnames, ports, domains, IP ranges, and the `hosts` topology map. A change here ripples through every service on every host.
- `hosts/homolab/services/ai/omniroute.nix` — OpenAI-compatible proxy; touches auth and routing.
- `hosts/homolab/configuration/hardware-configuration.nix` — host-specific, regenerated via `just homolab-gen-hardware`.
- `scripts/alpine-bootstrap` — root SSH, static addresses, Tailscale, cgroups, kernel hardening, and nftables reachability.
- `hosts/lumo/home/services/monitoring.nix` — Grafana's proxy whitelist must remain `homolab.hosts.homolab.lan`; widening it permits header-injection admin bypass.
- `hosts/lumo/home/services/podman.nix` — rootful container runtime trust boundary.

### Secrets helpers

```sh
just secret-encrypt sensitive/hosts/m3air/forgejo.yaml ./forgejo.yaml
just secret-decrypt sensitive/hosts/m3air/forgejo.yaml
just secret-edit sensitive/hosts/m3air/forgejo.yaml
```

Never commit plaintext secrets. Keep secret material in `sensitive/shared/` encrypted with `sops`.

Homolab secrets live under `sensitive/hosts/homolab/` (system secrets) and
`sensitive/hosts/homolab/home/` (per-user secrets). They are encrypted to both
the homolab age key *and* `m3air`, so they can be edited from `m3air` while the
server can still decrypt them at activation. Service modules under
`hosts/homolab/configuration/sensitive/*.nix` and `hosts/homolab/services/**`
reference these via `dotfiles + /sensitive/hosts/homolab/<file>`.

## Editor Rule Files

Checked locations:
- `.cursor/rules/`
- `.cursorrules`
- `.github/copilot-instructions.md`

None are present. `AGENTS.md` is the canonical instruction file in this repo.

## Documentation Scope

- Keep `README.md` concise and operator-facing.
- Keep detailed repo guidance in `AGENTS.md`.
- Put subsystem-specific detail close to the code, such as `common/home-gui/themegen/README.md`.

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
  imports = [ (dotfiles + /common/home-base) ./local-file.nix ];
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
- Current overlay packages: `blocky-bin`, `claude-code-bin`, `codex-cli-bin`, `default-browser`, `equibop-bin`, `framework-eww-state`, `kaguya-bin`, `ketch`, `pi-coding-agent-bin`, `rime-frost`, `rime-octagram-zh-hant-essay-bgw`, `themegen`, `utiluti`, `zed-bin`, `zen-bin`.
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

- `common/system/` is injected for NixOS and nix-darwin hosts. Standalone Home Manager hosts do not import system modules.
- `common/system-darwin/` is injected for darwin hosts only; `common/system-nixos/` for NixOS hosts only.
- `common/home-base/` is the CLI baseline, injected for every `features.homeManager = true` host.
- `common/home-alpine/` adds root-only Lix, direct sops activation, and Alpine root-shell wiring for standalone Home Manager hosts.
- `common/home-gui/` is injected when `features.gui = true`. GUI-only tools (ghostty, vscodium, zed, rime, themegen, zen-bin, etc.) live here and are not imported by server hosts.
- `common/home-base/agent-skills.nix` installs curated reusable skills into
  `$HOME/.skills`, then exposes Codex-compatible adapters under
  `$HOME/.agents/skills` and `$HOME/.codex/skills`. Keep `$HOME/.skills` as the
  agent-neutral source of truth, and do not manage generated system skills,
  sessions, memory data, auth state, plugin caches, or screen recordings from
  this repo.
- `themegen/` contains root-level plain templates split into `common/`, `m3air/`, and `framework/`; paths are `$HOME`-relative with no `home/` segment. `common/home-gui/themegen/default.nix` renders concrete files in the Nix store for Home Manager to install. `just theme` only renders a local `.cache/themegen/<host>/` copy for inspection.
- `common/home-gui/rime/` copies Rime Frost data into the host Rime user directory, enables Traditional Chinese by default with `s2tw.json`, and installs the `zh-hant-t-essay-bgw` octagram model. macOS uses the `squirrel-app` Homebrew cask; Linux uses Home Manager's Fcitx5 input method module with `fcitx5-rime`.
- `common/home-gui/themegen/` supports wallpaper-driven theme generation. `default.nix` auto-discovers plain templates under `themegen/common/` plus `themegen/<host>/`, builds a host-specific render derivation, exposes it as `themegenCache` for Framework GTK wrapping, and installs outputs through `home.file`.
- `hosts/<name>/` contains machine-specific choices only. The `host.nix` spec is the single file to create when adding a host.
- `hosts/<name>/wallpaper.*` is a symlink to `assets/` used by `just theme` and `just theme-preview` for the convention-based wallpaper lookup.
- `framework` is NixOS with Home Manager wired in by `mk-host`. The `nirinit` NixOS module is injected via `features.nirinit = true` in `hosts/framework/host.nix`.
- `hosts/framework/configuration/` is the active NixOS entrypoint; `hosts/framework/home/` contains user-level modules. `hosts/framework/overlay.nix` holds the framework-only kernel pin.
- `hosts/framework/home/eww/` runs the Framework Eww status bar; theme files come from `themegen/framework/.config/eww/`.
- `hosts/framework/home/niri-config.kdl` is the Framework Niri compositor config installed through Home Manager.
- `hosts/framework/configuration/grub-theme.nix` builds the Framework GRUB theme from repo assets.
- `hosts/m3air/home/appearance.nix` builds and launches the macOS Swift appearance scheduler from `appearance-scheduler.swift`.
- `hosts/m3air/home/default-apps.nix` uses `default-browser` and `utiluti` to manage default browser and default editor associations on macOS.
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

## Commit Messages

Use Conventional Commits with this subject format:

```text
topic(machine/scope): subject
```

- `topic` is the Conventional Commit type, such as `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `build`, `ci`, or `chore`.
- `machine` is the affected host or layer, such as `m3air`, `framework`, `common`, `pkgs`, or `repo`.
- `scope` is the focused area, package, or module, such as `home`, `niri`, `themegen`, `rime`, or `flake`.
- Keep `subject` short, imperative, and lowercase unless it contains proper nouns.

Examples:

```text
feat(framework/niri): add workspace keybindings
fix(m3air/default-apps): update browser associations
docs(repo/agents): document commit message format
```
