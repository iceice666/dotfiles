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
    agent-instructions.nix # shared agent-neutral global instructions
    agent-skills.nix # shared agent-agnostic personal skills
    dev-env.nix      # developer environment PATH/ENV (features.devEnv)
    pi.nix           # Pi binary, extensions, CLIProxyAPI models and runtime SOPS key lookup (features.pi)
    pi/              # repo-owned Pi extensions, tests and development dependencies
  home-gui/          # GUI workstation baseline (features.gui)
    default.nix      # imports app-defaults, ghostty, packages-gui, vscodium, zed
    packages-gui.nix # GUI binaries: equibop-bin, helium-bin, …
    app-defaults.nix # XDG MIME associations
    ghostty.nix      # fork Ghostty config with left-side vertical tabs
    vscodium.nix     # VSCodium config + marketplace wiring
    zed.nix          # Zed config
    rime/            # Rime Frost setup with Traditional Chinese octagram model (features.rime)
    themegen/        # wallpaper-driven theme generation (features.themegen)

themegen/            # root-level plain theme templates, split by common/host
  common/            # shared $HOME-relative templates for shells/editors/terminal
  m5pro/             # macOS-only $HOME-relative templates
  framework/         # Linux-only $HOME-relative templates for GTK/Qt/fuzzel/AGS
  preview.html       # HTML palette preview template

hosts/               # per-host entrypoints
  m5pro/             # macOS via nix-darwin
    host.nix         # feature manifest
    configuration/   # default.nix, system-defaults.nix
    home/            # appearance, default-apps, karabiner, wallpaper, _module.args
    wallpaper.jpg    # symlink → assets/win_chan.jpg
  framework/         # NixOS system with Home Manager
    host.nix         # feature manifest
    configuration/   # active NixOS system entrypoint, hardware, GRUB theme
    home/            # GUI/Niri/AGS Home Manager modules, wallpaper.nix rotation
  framework-installer/ # UEFI-only Framework reinstall ISO, embedded source + explicit install tool
  lumo/              # Alpine 3.24 server (aarch64, Raspberry Pi 5), data+apps + DNS + edge plane
    host.nix         # standalone root Home Manager + deploy-rs metadata
    home/services/   # Nix binaries, generated configs, OpenRC activation, Blocky DNS
    home/services/edge/ # edge stack (Traefik/Authelia/Cloudflare) moved from the retired gateway Pi
  worker/            # Alpine 3.24 (aarch64, ex-gateway Pi): disposable work / agent runtime, state on lumo
    host.nix         # standalone root Home Manager + deploy-rs metadata
    home/services/   # podman runtime + minimal firewall

lib/                 # shared nix helpers and local flake framework
  flake/             # auto-discovery, mk-host, home-manager wiring, overlays/, deploy, formatter, devshell outputs
  lab.nix            # shared hostnames, ports, domains, and IP ranges for lumo/worker

pkgs/                # overlay packages
  blocky-bin/        # official prebuilt Blocky DNS proxy releases
  cliproxyapi-account-quota/ # Go plugin reserving a share of Codex/Claude five-hour and weekly quotas
  cliproxyapi-bin/    # official prebuilt CLIProxyAPI releases
  default-browser/   # macOS default browser helper
  equibop-bin/       # Equibop binary
  framework-shell-state/ # Rust state daemon/action helper for Framework AGS
  helium-bin/        # Helium Browser package (macOS DMG / Linux AppImage)
  pi-bin/           # pinned upstream npm Pi on Node with managed TLS trust
  rime-frost/        # Rime Frost schema data
  rime-octagram-zh-hant-essay-bgw/ # Traditional Chinese octagram grammar model
  themegen/          # Rust-based theme generator (Cargo project)
  utiluti/           # macOS utility for default app associations
  zed-bin/           # Zed official prebuilt releases

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
| `ags` | `github:Aylur/ags/v3.1.2` (Framework GTK4 shell; matching Astal follows upstream lock) | yes |
| `ghostty` | `github:iceice666/ghostty/1a9d07c00fc78d8ace9897d3c1d9fc101c23a2ee` (fork with vertical tabs) | no |
| `pirc` | `github:iceice666/pirc/v0.10.0` (release-pinned; overlay adds `pkgs.pirc-gateway` and `pkgs.pirc-node`; lumo's `pirc.nix` uses `pirc-gateway`; homolab (WSL) runs a manually built `pirc-node`; bump the tag in `flake.nix`, then run `just update pirc`; back up both services' state before coordinated upgrades) | yes |
| `reimu-on-starlit-water` | `path:/home/iceice666/code/reimu_lays_on_water` | no |
`self.submodules = true` is set so Git submodules are fetched.

Theme files are generated by `common/home-gui/themegen/default.nix` as host-specific
Nix derivations from each host wallpaper plus `themegen/common/` and
`themegen/<host>/` templates.


### Outputs

| Output | Type |
|---|---|
| `darwinConfigurations.m5pro` | nix-darwin configuration |
| `nixosConfigurations.framework` | NixOS configuration |
| `nixosConfigurations.framework-installer` | minimal UEFI Framework reinstall ISO (`config.system.build.isoImage`) |
| `homeConfigurations.lumo` | Alpine root Home Manager data+apps + DNS + edge configuration |
| `homeConfigurations.worker` | Alpine root Home Manager disposable-work / agent-runtime host |
| `deploy` | deploy-rs node definitions for `framework`, `lumo`, and `worker` |
| `checks.x86_64-linux` | deploy-rs schema validation checks |
| `devShells.aarch64-darwin.default` / `devShells.x86_64-linux.default` | Rust/themegen development shell (includes `deploy`) |
| `formatter.aarch64-darwin` / `formatter.x86_64-linux` | treefmt |
| `packages.<system>.*` | standalone overlay packages (themegen, pi-bin, cliproxyapi-bin, …) |

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
| `pi` | `common/home-base/pi.nix` (binary and configuration) |

**Adding a host:** create `hosts/<new>/host.nix` with `{ inputs, dotfiles, name }:` signature, declare `features`, and add `homeModules = [ ./home ]`. The host appears as a flake output automatically.

### Overlay

The overlay is split into focused files under `lib/flake/overlays/`:

- `lix.nix` — inherits `nix-eval-jobs`, `nix-fast-build`, `nixpkgs-review` from `pkgs.lixPackageSets.stable`.
- `binaries.nix` — binary and cross-platform packages: `blocky-bin`, `cliproxyapi-account-quota`, `cliproxyapi-bin`, `default-browser`, `equibop-bin`, `framework-shell-state`, `helium-bin`, `pi-bin`, `rime-frost`, `rime-octagram-zh-hant-essay-bgw`, `themegen`, `utiluti`, `zed-bin`.
- `linux-gui.nix` — Linux-only packages: `kaguya-bin`, `niri-scratchpad-helper`, `reimu-on-starlit-water`. Attributes are omitted (not thrown) on non-Linux.
- `global-patches.nix` — `direnv` build fix (strips `-linkmode=external` from Makefile).
- `nodejs.nix` — temporary official Node.js binary pins through `pkgs/nodejs-bin`: 24.22.1 for the CLI/Pi and 22.23.4 for consumers such as Bitwarden. Hash-pinned binaries include patched bundled dependencies and avoid compiling V8 on Raspberry Pi hosts. Remove the override once both locked package sets provide equivalent fixes; retain the regression tests in `scripts/tests/test-nodejs-security.mjs`.

Framework uses nixpkgs' `linuxPackages_zen` directly so kernel security fixes
arrive with `just update nixpkgs`. Do not reintroduce a local pin to an
end-of-life kernel series; if a pin is ever needed, keep it on a supported
kernel.org branch and remove it once nixpkgs catches up.

Additional notes:
- `reimu-on-starlit-water` imports the local package expression from `/home/iceice666/code/reimu_lays_on_water/nix/package.nix` through a non-flake path input and builds it with the `nixpkgs-unstable` Rust toolchain.
- `helium-bin` is the local package under `pkgs/helium-bin`: the Helium macOS DMG on Darwin and the Helium Linux AppImage (via `appimageTools`) on Linux. m5pro and Framework use it as their default browser.

### Node.js security updates

The shared overlay updates both `nodejs-slim_22`/`nodejs-slim_24` and their
npm/corepack wrappers, including the default `nodejs` alias. Updating only
`home.packages` does not update absolute runtime paths embedded in Pi,
Playwright, or Bitwarden. `pkgs/nodejs-bin` packages official binaries for native
Linux/macOS x86_64 and arm64; cross builds are rejected. Matching full source is
unpacked only for npm patches and node-gyp (no V8 compilation). The package does
not provide a static libv8 or V8 compiler-generator outputs. Its launcher defaults
to OpenSSL CA verification and the filtered bundle while permitting explicit
caller trust overrides; direct `process.execPath` execution with a cleared
environment bypasses these launcher defaults. Pi retains its explicit CA policy.
Run each built runtime against `scripts/tests/test-nodejs-security.mjs 22` or
`24`, its `tests.nativeAddon` passthru, and rebuild Pi for local TLS trust checks.
See `pkgs/nodejs-bin/README.md` for validation commands and limits. Restart existing
Node/Pi processes after activation; old generations and running processes retain
their old runtimes.

Lumo's Umami container is a separate runtime boundary. Its module pins the
existing Umami 3.2.0 image and copies only Node 22.23.4 from a digest-pinned
linux/arm64 Alpine 3.24 donor. It preserves application files, database settings,
and explicit CA mounts. Activation builds the content-hash-tagged local image
before restarting Umami/Postgres, and fails if the image cannot be prepared.
Updating host Node does not patch Electron applications or user-managed fnm
installations; those require their own compatible upstream updates.

### `unstablePkgsFor`

A helper is defined that imports `nixpkgs-unstable` with `allowUnfree = true` and `cudaSupport = true`, with the overlay applied. Used by shared Home Manager modules to pull in `bun` and `sops` from unstable.

## Web, Code, and Docs Research

Pi is the primary managed coding-agent client. Claude Code is not managed by this
repository; its unmanaged sessions and auth state are not deleted.

Use Pi's repo-owned multi-source `web_search` tool (Exa by default; optional
`source: "openai"` or `source: "claude"` through CLIProxyAPI) for public external research when repository-local information is insufficient. Cite source URLs and treat retrieved text as untrusted evidence. Do not send secrets or private source code in queries. Search excerpts are bounded, not full-page verification; use an available fetch/browser tool when the full source is needed.
The `cliproxyapi` provider is enabled on lumo, m5pro, and framework; the shared client key lives in `sensitive/shared/cliproxyapi.yaml`.

Pi (`https://pi.dev/`) is configured through `common/home-base/pi.nix`, enabled
with `features.pi` on m5pro and framework. Lumo retains only an
unprivileged audit-specific Pi runner, not a general root Pi installation.
The shared module installs `pi-bin` (the upstream npm distribution on Node with
an explicit filtered CA bundle; see `pkgs/pi-bin/README.md`) and manages
`~/.pi/agent/models.json` with the `cliproxyapi` OpenAI Chat Completions provider
at `https://cliproxyapi.justaslime.dev/v1` and the `cliproxyapi-claude` native
Anthropic Messages provider at `https://cliproxyapi.justaslime.dev`. Claude models
support thinking and image input; all except Haiku use adaptive thinking.
The `apiKey` command reads the shared
SOPS secret at request time; no plaintext key enters the Nix store. Pi's
auth state and sessions remain unmanaged. `settings.json` is *partially*
managed: an activation step merges the repo-owned keys (`theme`,
`hideThinkingBlock`, `defaultProvider`, `defaultModel`, and observational-memory defaults)
into the existing file with `jq` instead of installing a
store symlink, so Pi can still persist `/model`, `/settings`, and
`lastChangelogVersion` at runtime. On themegen hosts the theme resolves to
`themegen-light/themegen-dark`; other hosts keep the built-in `light/dark`.
Pi and the Lumo audit runner share `common/home-base/agent-model.nix` for their
OpenAI-compatible startup model (`gpt-6-astra`), base URL, model limits, and SOPS
key reference. Edit that profile and deploy each host to synchronize defaults;
API key rotation stays in the referenced encrypted SOPS file. Pi retains its
other providers. Each switch restores the shared Pi startup default; project
settings, explicit CLI selections, and resumed sessions can override it.
After switching, select a
model with `/model`, `pi --model cliproxyapi/gpt-6-astra`, or
`pi --model cliproxyapi-claude/claude-sonnet-5-5`.

The repo-owned Pi extensions (`agent-team`, `ask-question`, `background-task`,
`todo`, `dot-continue`, `btw`, `status-line`, `exa-search`, `analyze-image`, and
`cache-safe-compaction`) are owned by `common/home-base/pi/extensions/` and
built into one Nix store tree on all Pi-enabled hosts; only the managed `pi` launcher
loads it (`--no-extensions` plus explicit store paths). `~/.pi/agent/extensions/`
receives only `unmanaged-pi-guard.ts`, which blocks every tool in an unmanaged Pi
(e.g. a Bun/npm global install earlier on `PATH`; `dev-env.nix` appends
`~/.bun/bin` so it cannot shadow the launcher). Restart Pi after switching. The
same extension tree includes the Nix-pinned upstream `pi-observational-memory`
source, patched by `common/home-base/pi/patches/` so background memory work
falls back from a rate-limited `cliproxyapi/gpt-6.1-sol` to
`cliproxyapi-claude/claude-sonnet-5-5` for a bounded cooldown. The patch is tied
to the pinned upstream tag and also adapts its agents to Pi 1.2.0's transcript
system messages and `finishTurn` boundaries: regenerate and re-run the upstream
test suite and type check against the pinned Pi SDK when bumping either version.
Keep sibling directories together: agent-team imports ask-question's
service. Observational Memory owns `session_before_compact`; the cache-safe
extension observes only `session_compact` and must not compete for summary
ownership.
Bash is installed explicitly for background jobs; the shared CLI baseline supplies
Git and Node.js. Runtime state stays unmanaged. Extensions run with the invoking
user's full permissions, including root on lumo, as a trusted control plane.
The managed `pi` wrapper pins the repo extension tree and disables project
executable resources, but does not provide an OS sandbox. Upstream file/shell
tools, background jobs, verification and workers use normal user permissions,
environment, network and filesystem access. `local-process.mjs` shares ordinary
process plans using launcher-pinned Bash/Node/Git. Seatbelt/bubblewrap adapters,
workspace scans and the `/sandbox` command have been removed. Auto Mode has also
been removed, including per-tool model review, `/auto`, `/yolo`, file-scope grants
and the worker review-context bridge. The managed launcher and unmanaged-Pi guard
remain; tools and workers run with normal host permissions, without OS isolation.
Todo tasks with explicit human-approved `checks` still require fresh captured
execution evidence before completion. Declaration approval lives independently in
`common/home-base/pi/extensions/ask-question/approval.ts` and routes worker
requests through the authenticated team broker; cancellation or unavailable UI
never approves a declaration. See `common/home-base/pi/extensions/todo/README.md`.
See `common/home-base/pi/README.md` for first-adoption backups and development.
`/btw <question>` runs a separate tool-free call using the selected model and a
bounded conversation snapshot while the main agent continues. Its persisted
custom-entry answer is display-only, never main-agent context; `/btw cancel`
cancels only the side request. See `common/home-base/pi/extensions/btw/README.md`.
Do not force-overwrite existing unmanaged extensions or install duplicate copies
via `pi install`.

Pi also installs the shared agent-neutral instructions at `~/.pi/agent/AGENTS.md`.
`/skill:next-milestone` discovers the shared skill through `~/.agents/skills` and
loads `workflows/pi.md` for the team/todo/review mapping. Exa's `web_search` reads
`~/.pi/agent/exa-api-key` at request time; the helper reads the SOPS secret, with
no plaintext key in the Nix store or settings. The Exa search endpoint is fixed to
`https://api.exa.ai/search`. Optional OpenAI/Claude search uses the existing
`cliproxyapi`/`cliproxyapi-claude` provider credentials with fixed
`https://cliproxyapi.justaslime.dev/v1/responses` and `/v1/messages` endpoints.
Native search requires successful search evidence and labels model synthesis
separately from sources; there is no extension-level retry or automatic fallback.
Unmanaged settings keys, auth state, and session state are left alone.

`analyze_image` delegates local PNG/JPEG/GIF/WebP analysis to a configured vision
model (default `cliproxyapi-claude/claude-sonnet-5-5`) and returns text for text-only
models. It uses registry-managed auth, sends only the image and question (no
history/tools), and enforces file/output limits plus cancellation/deadlines.
Images leave the host; do not send sensitive content without authorization.
See `common/home-base/pi/extensions/analyze-image/README.md` for details.

The active lumo daily audit reporter uses an audit-only Pi runner with the shared
`agent-model.nix` profile (`cliproxyapi/gpt-6-astra`). Root collects evidence and
sends mail through Resend; `runuser` runs Pi as the non-login `homolab-audit`
account and the runner refuses UID 0 or any other account. Root-owned evidence
is group-readable but not writable by that account. Each report uses a private
0700 temporary agent directory under `/run/homolab-audit`, a sanitized environment,
and a 0400 copy of only the model API key; the directory is removed on exit.
The account cannot read the root SOPS identity, original secrets, or Resend key.
The fixed runner invokes the pinned `pi-bin` directly with `--tools read,ls`,
`--no-approve`, and extension/skill/context/theme discovery disabled; it does not
load the interactive managed extension tree. This is Unix privilege separation,
not an OS sandbox or a bundle-only filesystem boundary: world-readable host files
remain readable. Model stderr is saved as root-only `pi-output.log`; reports and
mail artifacts are also root-only. Switching removes root's managed Pi launcher
and symlinked config, but leaves unmanaged `/root/.pi` settings/auth/sessions
untouched; old generations still retain their previous closures until collected.
`just update-pkgs` invokes Pi with the repo-local skill at
`.agents/skills/update-pkgs/SKILL.md` on a Pi-enabled workstation.

Forgejo and Woodpecker on lumo are temporarily offline. Their module, encrypted
secrets, and persistent data are retained. `lumo.forgejoWoodpecker.enable` defaults
to `false`; activation stops the stack and removes its default-runlevel entries,
and Traefik omits its routes. Re-enable only after resolving the image's auxiliary
OpenSSH listener conflict with host port 22. `just lumo-smoke` expects the stack
to remain offline.

The lumo audit collector discovers OpenRC commands through the system PATH,
collects file-based sysklogd logs and bounded rotated-log tails, and records
individual service status exit codes. Missing or truncated logs do not establish
complete 24-hour authentication coverage. It also records patch-level evidence:
`apk list --upgradable` after a repository refresh, the installed-vs-running
`linux-rpi` kernel, core APK versions, the Nix-provided service versions of the
active generation, and Trivy HIGH/CRITICAL scans of the Alpine package database
(`/nix`, `/var`, and container storage skipped) and of the images backing
running containers (fixed-only). Trivy caches its database root-only under
`/var/cache/trivy` and needs outbound access to ghcr.io; scan failures are
recorded as collector gaps, not clean results. Nix closures are not CVE-scanned.

## TLS trust and the October 2026 eMudhra incident

`lib/tls-ca-blacklist.nix` owns the four NSS labels removed by the current
Mozilla/NixOS response. `common/system` applies them to NixOS/nix-darwin;
`dotfiles-cacert` in the shared overlay supplies an explicit plain bundle for
Pi, CLI session variables, and configured containers without rebuilding every
package in nixpkgs. Session variables apply to new sessions, not every daemon or
application's embedded store. Preserve local/custom CA requirements deliberately
when changing these paths.

Alpine activation installs the full APK `ca-certificates` package if missing,
records disabled source entries, and regenerates its bundle without discarding
local certificates. It does not upgrade APK packages on every activation.
macOS activation runs `scripts/tls-trust-macos.py`: it backs up the native
`/etc/ssl/cert.pem` once, adds System keychain deny entries from the four
fingerprint-verified public PEMs in `common/system-darwin/tls-distrust-roots.pem`,
and atomically filters the native PEM bundle. It requires interactive operator
privilege when sudo is unavailable. `--check` only inspects PEM membership, not
keychain state or every application verifier.

Bun is temporarily pinned to the official patched
`1.4.4-canary.1+963452075` assets with fixed hashes, explicitly approved by the
operator. The canary URL is rolling: replacement causes a hash failure, never a
silent update. Replace this exception with a verified fixed stable release when
available. Pi instead uses its supported npm/Node distribution at the same SDK
version; updating external Bun cannot update an already compiled standalone Pi.

Run `python3 scripts/tests/test-alpine-trust.py` and
`python3 scripts/tests/test-tls-trust-macos.py` for non-destructive fixtures.
`scripts/tls-trust-probe.mjs` tests a positive control and all twelve public
compromised-chain endpoints; it never authenticates. Require certificate errors,
not generic connection failures. Existing processes must be restarted after
activation. Managed browser profiles need separate fresh-process verification:
Playwright disables component updates by default, and pre-seeded CRLSets load
asynchronously, so a successful CLI probe does not establish browser safety.
Do not use an unverified managed browser for sensitive browsing.

## Managed browser access

m5pro and Framework explicitly import `common/home-base/browser.nix`. It installs
`pkgs/playwright-cli` (pinned `@playwright/cli` plus `playwright-read` for rendered
Markdown extraction), the `playwright-browser` skill, and the global Playwright
CLI config. No MCP bridge or extra Pi extension is required. macOS uses packaged
Helium; Framework uses packaged Chromium, with isolated profiles and the browser
sandbox explicitly enabled. Lumo is not enabled.

Use unique task/worker session names and close only owned sessions. Never copy
personal profiles or disable the sandbox to fix startup errors. Project config,
environment and flags can override defaults; this is not agent isolation.
Authentication, browser state and artifacts stay out of the store and Git.
See `pkgs/playwright-cli/README.md` for setup, limits and test commands.

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
`nixos-rebuild`, or `home-manager` commands.


Framework full-disk reinstallation uses `just framework-iso`, which builds the
`framework-installer` host without activating it. Its source snapshot includes
tracked encrypted secrets but never identities. `scripts/framework-install`
requires a local console, UEFI, an unused whole disk, an explicit swap size and
exact erasure confirmation; it dry-runs the online build plan before wiping, then
builds into the target disk store after erasure (not the Live RAM store). It creates
the existing Btrfs subvolumes and patches only the installed source copy's EFI
UUID to `NIXOS_BOOT`. No destructive command runs on boot. Run
`just framework-install-test` for safe fixture tests; never execute the destructive
path on a real host as validation. See `hosts/framework-installer/README.md` for
backups, credential recovery, and disposable UEFI VM validation.

Fingerprint authentication is configured in
`hosts/framework/configuration/default.nix` through `services.fprintd.enable`
and `security.pam.services.{greetd,sudo}.fprintAuth`. Keep `fprintd` in the
Framework system packages so `fprintd-enroll` and related tools are available
for enrollment and troubleshooting.

Framework appearance scheduling is configured in `hosts/framework/home/gui.nix`
with Home Manager's `services.darkman`. It uses coarse Taipei coordinates from
the Framework timezone, exposes darkman through the XDG Settings portal, and
runs GTK/GNOME color-scheme scripts on sunrise/sunset transitions.

Framework wallpaper rotation lives in `hosts/framework/home/wallpaper.nix`.
`host.nix` lists the set as `desktopWallpapers` (files under `assets/`, unique
stems); `desktopWallpaper` stays the static regreet login background. Every
wallpaper gets its own themegen render plus AGS CSS and `Themegen{,-dark}` GTK
theme dirs at build time. The `framework-wallpaper` helper copies the chosen
bundle to `~/.local/state/themegen/current`, which all themegen Home Manager
links point at, then reloads apps (darkman appearance links, GTK name bounce,
link nudges for Zed/Pi/Equibop dir watchers, kitty `SIGUSR1`, fish
`themegen_generation` uvar, AGS restart, `awww img`). The darkman hook rotates to a
random different wallpaper only when the mode actually changes (sunrise/sunset
or a manual toggle); logins and `just switch` keep the current one.
`framework-wallpaper next` rotates manually. awww replaces swaybg.
libadwaita apps pick up new colors only after restarting.

### Primary workflows

```sh
just build
just switch
just boot

just theme
just theme-preview
just fmt
just fmt-check
just check
```

- `just build` and `just switch` are platform-gated duplicate recipes: macOS maps to `m5pro`, and Linux detects the hostname to pick the NixOS host (`framework`).
- `just boot` is Linux-only and sets the current NixOS host generation for next boot.
- Theme files are generated inside the host build by a Nix derivation.
- `just theme` generates a local concrete theme cache for inspection only.
- `just fmt` runs `nix fmt` through `treefmt-nix` (nixfmt + just formatters).
- `just check` runs format, Justfile metadata, and `nix flake check --all-systems`.
- Recipe groups and platform guards use official `just` attributes such as `[group('host')]`, `[macos]`, and `[linux]`.

### Dry builds / targeted validation

Before building any Nix configuration, run `git add` on new or untracked files so Nix's flake evaluation can see them. Verify with `git status` that no required `.nix` files remain untracked.

There is no unit-test suite. The closest equivalent is the narrowest host build that covers the change.

```sh
just build
```

Run it on the platform that owns the changed host. For shared changes, dry-build
on both `m5pro` and `framework`.

Which build to run for a given change:

| Changed path | Dry-build target(s) |
|---|---|
| `hosts/m5pro/**` | `m5pro` |
| `hosts/framework/home/**` | `framework` |
| `hosts/framework/configuration/**` | `framework` |
| `hosts/framework-installer/**`, `scripts/framework-install` | `just framework-install-test` + `just framework-iso` |
| `hosts/lumo/**` | `lumo` (via `just lumo-build`) |
| `hosts/worker/**` | `worker` (via `just worker-build`) |
| `lib/lab.nix` | `m5pro` + `framework` + `lumo` + `worker` |
| `common/system/**` | `m5pro` + `framework` |
| `common/system-darwin/**` | `m5pro` |
| `common/system-nixos/**` | `framework` |
| `common/home-base/**` | all Home Manager-enabled hosts |
| `common/home-alpine/**` | `lumo` + `worker` |
| `common/home-gui/**` | `m5pro` + `framework` |
| `pkgs/<name>` | `nix build .#<name>` (standalone) or any host that uses it |

### Other useful commands

```sh
just update
just update nixpkgs
just search <query>
just gc
just store-size
```

`just gc` runs `scripts/nix-gc`. On macOS, App Management blocks deleting a
`/nix/store` `.app` that macOS tagged with `com.apple.macl` (it was launched
from the store). When GC aborts on such a path after dropping its database row,
the script removes only that now-invalid path with `/bin/rm` and retries. The
terminal running it needs App Management permission. To avoid new tags, launch
only the copied `~/Applications/Home Manager Apps` bundles: m5pro activation
unregisters store bundles from Launch Services, and Playwright uses the copied
Helium.

### Host-specific helpers

```sh
just m5pro-homebrew    # install Homebrew (first-time macOS setup)
just m5pro-activate    # reapply macOS settings without a full rebuild

just lumo-bootstrap          # converge the existing Alpine 3.24 lumo installation
just lumo-build              # dry-activate lumo root Home Manager
just lumo-switch             # deploy lumo root Home Manager
just lumo-smoke              # verify lumo OpenRC services and local endpoints
just lumo-upgrade [apply]    # refresh/upgrade lumo's APK layer (kernel, OpenSSH, Tailscale); dry run by default
just cliproxyapi-reset-cooldown [provider] # clear CLIProxyAPI cooldowns (default codex) after an upstream quota reset

just worker-bootstrap 192.168.1.129  # converge the ex-gateway Pi as worker (pass a reachable target)
just worker-build            # dry-activate worker root Home Manager
just worker-switch           # deploy worker root Home Manager
just worker-upgrade [apply]  # refresh/upgrade worker's APK layer; dry run by default
```

Nothing else upgrades APK packages on either Alpine host: Home Manager owns the
Nix side only, and activation never runs `apk upgrade`. `scripts/alpine-upgrade`
prints pending upgrades, applies them only with `apply`, compares the installed
`linux-rpi` package to the running kernel, and prints reboot/restart hints. It
never reboots or restarts services itself.

`lumo` runs Alpine Linux 3.24 with root-only Lix installed using `--init none`.
deploy-rs activates the standalone root Home Manager profile and builds the
aarch64 closure on its target. Alpine/APK owns boot, the kernel, networking,
OpenSSH, Tailscale, cgroups, and the nftables launcher. Home Manager owns root
tooling and Nix-provided application services supervised by OpenRC — including
Blocky DNS and the edge stack (Traefik/Authelia/Cloudflare DDNS) that moved off
the retired gateway Pi.

`lumo` is the data+apps+DNS plane: Postgres, Valkey, git-server, Podman,
Blocky, Prometheus, Dynacat, CLIProxyAPI, Umami, and the daily audit.
Application backends (Dynacat, Umami, CLIProxyAPI, Prometheus, Authelia) bind
to loopback and are reached only through lumo's local Traefik. The lumo
firewall accepts only SSH, Blocky DNS, and HTTP/HTTPS on `tailscale0`, and only
DNS and HTTP/HTTPS from `podman*`; do not reintroduce blanket interface trust or
wildcard backend listeners. Prometheus scrapes only lumo's local exporters, and
Traefik's ping/metrics entry points bind to loopback (no LAN firewall rule).
Every websecure router carries the `security-headers` middleware (HSTS with
subdomains, nosniff, SAMEORIGIN, strict referrer) and the default TLS options
require TLS 1.2+, strict SNI, and ECDHE AEAD suites. The whole CLIProxyAPI
host, including `/v1`, is restricted to loopback/LAN/tailnet client IPs: Pi
clients reach it over the tailnet because Blocky maps the name to lumo's
tailnet address, and public requests through Cloudflare get a 404. lumo's own
resolver order is not reliable for these names (Tailscale falls back to the base
`1.1.1.1` entry because the tailnet resolver is lumo itself), so `blocky.nix`
also maintains a marker-delimited `/etc/hosts` block mapping every private name
to the tailnet address; glibc-linked Nix binaries such as the audit Pi depend
on it. Traefik entry points use `aliasHeadersStrategy = delete`, dropping any
request header whose name is not letters, digits, and dashes. Authelia's
`regulation` bans an account for 10 minutes after 3 failed attempts within 2
minutes. Rootful container images in `umami.nix` and
`cliproxyapi-usage-keeper.nix` are digest-pinned; bump digests deliberately.

Blocky listens on lumo's Tailscale address (`100.120.152.7`) on TCP/UDP 53.
Its HTTP/Prometheus listener is loopback-only on port 4000; Traefik publishes
DoH at `https://dns.justaslime.dev/dns-query`. The tailnet global nameserver
must point to `100.120.152.7`.

After provisioning either Alpine board:
1. Run `just <host>-bootstrap`; it installs host primitives and prints the age recipient.
2. Add the recipient anchor and host rule entry to `.sops.yaml`.
3. Re-encrypt host secrets with `just secret-refresh sensitive/hosts/<host>`.
4. Run `just <host>-build`, then `just <host>-switch`.
5. Reboot and run `just lumo-smoke` for lumo.

### Server danger areas

Touch these with care; misconfiguration affects the server's reachability or
trust boundary:

- `lib/lab.nix` — hostnames, ports, domains, IP ranges, and the `hosts` topology map. A change here ripples through every service on every host.
- `hosts/lumo/home/services/cliproxyapi.nix` — OpenAI-compatible proxy on lumo. Its `account-quota` scheduler polls each Codex/Claude OAuth usage endpoint, caches observations for `poll_interval_seconds` (900), and fails closed when it cannot verify the reserve per upstream `AuthID`. A reserve withholds the account once *either* the five-hour or the weekly window reaches its ceiling; the per-account percentages in `sensitive/hosts/lumo/account-quota.yaml` cover both windows unless a `weekly_reserve_percent_by_auth_id` entry overrides the weekly one. Changes touch auth and routing.
- `scripts/alpine-bootstrap` — root SSH, static addresses, Tailscale, cgroups, kernel hardening, and nftables reachability.
- `hosts/lumo/home/services/edge/nftables.nix` — lumo inbound policy; mirror changes into `scripts/alpine-bootstrap`.
- `hosts/lumo/home/services/podman.nix` — rootful container runtime trust boundary.

### Secrets helpers

```sh
just secret-encrypt sensitive/hosts/m5pro/forgejo.yaml ./forgejo.yaml
just secret-decrypt sensitive/hosts/m5pro/forgejo.yaml
just secret-edit sensitive/hosts/m5pro/forgejo.yaml
```

Never commit plaintext secrets. Keep secret material in `sensitive/shared/` encrypted with `sops`.

`m5pro` and `framework` are both admin recipients in `.sops.yaml`: every
creation rule lists both, so any secret is readable and editable from either
workstation. Server secrets also carry the owning host key (`lumo`, `worker`) so activation can decrypt them locally. On
`framework` the age identity is derived from `~/.ssh/id_ed25519` through
`SOPS_AGE_KEY_CMD` (`common/home-base/default.nix`); no separate
`keys.txt` is required.

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
```text
topic(machine/scope): subject
```

- `topic` is the Conventional Commit type, such as `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `build`, `ci`, or `chore`.
- `machine` is the affected host or layer, such as `m5pro`, `framework`, `common`, `pkgs`, or `repo`.
- `scope` is the focused area, package, or module, such as `home`, `niri`, `themegen`, `rime`, or `flake`.
- Keep `subject` short, imperative, and lowercase unless it contains proper nouns.

Examples:

```text
feat(framework/niri): add workspace keybindings
fix(m5pro/default-apps): update browser associations
docs(repo/agents): document commit message format
feat(lumo/hermes-agent): deploy hermes-agent gateway via podman
```
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
- Current overlay packages: `blocky-bin`, `cliproxyapi-account-quota`, `cliproxyapi-bin`, `default-browser`, `equibop-bin`, `framework-shell-state`, `helium-bin`, `kaguya-bin`, `pi-bin`, `rime-frost`, `rime-octagram-zh-hant-essay-bgw`, `themegen`, `utiluti`, `zed-bin`.
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
- `common/home-gui/` is injected when `features.gui = true`. GUI tools (ghostty, vscodium, zed, rime, themegen, helium-bin, etc.) live here; server hosts do not import the baseline.
- `common/home-base/agent-skills.nix` installs curated reusable skills into
  `$HOME/.skills`, then symlinks each into `$HOME/.agents/skills` for Pi discovery.
  Each skill's `SKILL.md` must stay agent-neutral prose (no tool-specific
  vocabulary like a particular todo/task/eval API). Pi-specific execution
  detail — concrete tool/API mappings for the steps that benefit from it —
  lives beside the skill under `workflows/pi.md`; `SKILL.md` tells the agent
  to check for and read a matching adapter. Only the Pi adapter is maintained;
  no client-specific skill links or commands are installed for other agents.
  Do not manage generated system skills, sessions, memory data, auth state,
  plugin caches, or screen recordings from this repo.
- `common/home-base/agent-instructions.nix` installs the repo-owned agent-neutral
  global instructions at `$HOME/.agents/AGENTS.md`; `pi.nix` installs the same
  source at `$HOME/.pi/agent/AGENTS.md` on Pi-enabled hosts.
- `themegen/` contains root-level plain templates split into `common/`, `m5pro/`, and `framework/`; paths are `$HOME`-relative with no `home/` segment. `common/home-gui/themegen/default.nix` renders concrete files in the Nix store for Home Manager to install. `just theme` only renders a local `.cache/themegen/<host>/` copy for inspection.
- `common/home-gui/rime/` copies Rime Frost data into the host Rime user directory, enables Traditional Chinese by default with `s2tw.json`, and installs the `zh-hant-t-essay-bgw` octagram model. macOS uses the `squirrel-app` Homebrew cask; Linux uses Home Manager's Fcitx5 input method module with `fcitx5-rime`.
- `common/home-gui/themegen/` supports wallpaper-driven theme generation. `default.nix` auto-discovers plain templates under `themegen/common/` plus `themegen/<host>/`, builds a host-specific render derivation, exposes it as `themegenCache` for Framework GTK wrapping, and installs outputs through `home.file`.
- `common/home-gui/ghostty.nix` manages the pinned `iceice666/ghostty` fork,
  with `window-tab-bar-position = left`, `window-show-tab-bar = always`, and
  host-specific `ghosttyFontSize`. Themegen hosts select
  `light:themegen-light,dark:themegen-dark` from generated native themes under
  `$HOME/.config/ghostty/themes/`. Linux uses the fork's flake package through
  `pkgs.ghostty`; Darwin uses the arm64 release app bundle packaged by
  `pkgs/ghostty-bin/default.nix` through the same overlay attribute. The macOS
  bundle is ad-hoc signed, not notarized; Gatekeeper may require explicit
  approval before the first launch. Packaging does not establish a verified
  interactive launch or deployment.
- `hosts/<name>/` contains machine-specific choices only. The `host.nix` spec is the single file to create when adding a host.
- `hosts/<name>/wallpaper.*` is a symlink to `assets/` used by `just theme` and `just theme-preview` for the convention-based wallpaper lookup.
- `framework` is NixOS with Home Manager wired in by `mk-host`.
- `hosts/framework/configuration/` is the active NixOS entrypoint; `hosts/framework/home/` contains user-level modules.
- `hosts/framework/home/ags/` runs the Framework AGS 3 / Astal GTK4 shell (`framework-ags.service`), pinned through the upstream AGS flake with its matching Astal libraries. It provides per-monitor bars, StatusNotifier tray/GTK4 menus, calendar, and a Material/GNOME-inspired control center. `state.ts` adapts the Rust backend, `control-center.tsx` owns the panel, and `app.tsx` owns monitor/window lifecycle and the bar. Theme files come from `themegen/framework/.config/ags/`; AGS owns notifications through AstalNotifd (`notifications.tsx`: popups, center, unread badge, DND), with a D-Bus activation file pointing at `framework-ags.service` — there is no Mako. `pkgs/framework-shell-state/` emits UI-neutral JSON-line state patches and handles media keys. See the AGS directory's README for validation and migration notes.
- `hosts/framework/home/niri-config.kdl` is the Framework Niri compositor config installed through Home Manager.
- `hosts/framework/configuration/grub-theme.nix` builds the Framework GRUB theme from repo assets.
- `hosts/m5pro/home/appearance.nix` builds and launches the macOS Swift appearance scheduler from `appearance-scheduler.swift`.
- `hosts/m5pro/home/default-apps.nix` uses `default-browser` and `utiluti` to manage default browser and default editor associations on macOS.
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
- `machine` is the affected host or layer, such as `m5pro`, `framework`, `common`, `pkgs`, or `repo`.
- `scope` is the focused area, package, or module, such as `home`, `niri`, `themegen`, `rime`, or `flake`.
- Keep `subject` short, imperative, and lowercase unless it contains proper nouns.

Examples:

```text
feat(framework/niri): add workspace keybindings
fix(m5pro/default-apps): update browser associations
docs(repo/agents): document commit message format
```
