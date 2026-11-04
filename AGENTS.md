# AGENTS.md - Repository Guide

Multi-host Nix dotfiles built on `flake.nix`, `nix-darwin`, `home-manager`,
`sops-nix`, `treefmt-nix`, and `just`. This file is the working agreement for
coding agents: how to change, validate, and commit. Architecture and subsystem
background live in the docs listed below. Read the relevant one before changing
that area.

## Where Things Live

| Path | Contents | Details |
|---|---|---|
| `flake.nix`, `lib/flake/` | inputs, host auto-discovery, `mk-host`, feature flags, overlays | `lib/flake/README.md` |
| `lib/lab.nix` | shared hostnames, ports, domains, IP ranges for lumo/worker | — |
| `common/system*/` | NixOS/nix-darwin system modules | `lib/flake/README.md` |
| `common/home-base/` | CLI baseline for every HM host | — |
| `common/home-base/agent-*` | agent-neutral global instructions (`~/.agents/AGENTS.md`, `~/.pi/agent/AGENTS.md`) and skills (`~/.skills` → `~/.agents/skills`) | — |
| `common/home-base/pi*` | managed Pi launcher, extensions, providers | `common/home-base/pi/README.md` |
| `common/home-alpine/` | root HM baseline for Alpine hosts | `common/home-alpine/README.md` |
| `common/home-gui/` | GUI workstation baseline (ghostty, zed, vscodium, rime, themegen) | `rime/README.md`, `themegen/README.md` |
| `themegen/` | `$HOME`-relative theme templates (`common/`, `m5pro/`, `framework/`) | `common/home-gui/themegen/README.md` |
| `hosts/m5pro/` | macOS (nix-darwin) | `hosts/m5pro/README.md` |
| `hosts/framework/` | NixOS laptop | `hosts/framework/README.md` |
| `hosts/framework-installer/` | UEFI reinstall ISO | `hosts/framework-installer/README.md` |
| `hosts/lumo/` | Alpine data/apps/DNS/edge server | `hosts/lumo/README.md` |
| `hosts/worker/` | Alpine disposable-work / agent-runtime host | `common/home-alpine/README.md` |
| `pkgs/<name>/` | overlay packages | per-package `README.md` where present |
| `scripts/` | implementations for complex `just` recipes, plus `scripts/tests/` | — |
| `sensitive/` | sops-encrypted secrets (`shared/`, `hosts/<name>/`) | — |
| `docs/tls-trust.md` | CA distrust, Node.js/Bun security pins | — |

Hosts are auto-discovered from `hosts/*/host.nix`; adding a host means creating
that one file (see `lib/flake/README.md`).

## Commands

Run from the repository root. Prefer `just` recipes over direct `nix build`,
`darwin-rebuild`, `nixos-rebuild`, or `home-manager`.

```sh
just build / just switch     # current platform host (macOS → m5pro, Linux → by hostname)
just boot                    # Linux only: set next-boot generation
just fmt / just fmt-check    # treefmt (nixfmt + just)
just check                   # format, Justfile metadata, nix flake check --all-systems
just theme / theme-preview   # local themegen cache / palette preview (inspection only)
just update [input]          # e.g. just update nixpkgs
just search <query> / just gc / just store-size
just <lumo|worker>-build / -switch / -bootstrap / -upgrade [apply]
just lumo-smoke
just framework-iso / just framework-install-test
just secret-encrypt|secret-decrypt|secret-edit|secret-refresh <path>
```

Recipes use `just` attributes such as `[group('host')]`, `[macos]`, `[linux]`.

## Validation

There is no unit-test suite for Nix modules; the closest equivalent is the
narrowest host build that covers the change. Before building, `git add` new or
untracked files so flake evaluation can see them, and confirm with `git status`.

| Changed path | Validate with |
|---|---|
| `hosts/m5pro/**`, `common/system-darwin/**` | `m5pro` build |
| `hosts/framework/**`, `common/system-nixos/**` | `framework` build |
| `hosts/framework-installer/**`, `scripts/framework-install` | `just framework-install-test` + `just framework-iso` |
| `hosts/lumo/**` | `just lumo-build` |
| `hosts/worker/**` | `just worker-build` |
| `common/home-alpine/**` | `lumo` + `worker` |
| `lib/lab.nix` | `m5pro` + `framework` + `lumo` + `worker` |
| `common/system/**`, `common/home-gui/**` | `m5pro` + `framework` |
| `common/home-base/**` | all Home Manager-enabled hosts |
| `common/home-base/pi/**` | Pi test suite (see Pi README) + Pi-enabled hosts |
| `pkgs/<name>` | `nix build .#<name>` or a host that uses it |
| TLS trust paths | `scripts/tests/test-alpine-trust.py`, `test-tls-trust-macos.py` (see `docs/tls-trust.md`) |

Run each build on the platform that owns the host. Then:

- formatting-sensitive files touched → `just fmt`;
- flake wiring or `common/` touched → `just check`;
- docs-only changes → careful reread and consistency pass.

Report which hosts were and were not actually built.

## Change Strategy

- Make the smallest structural change that matches existing patterns.
- Prefer extending an existing host/common module over adding parallel abstractions.
- `hosts/<name>/` holds machine-specific choices only; shared behavior goes in `common/`.
- Update the relevant doc when structure, commands, host wiring, or a documented
  invariant changes.

## Guardrails

### Secrets

- Never commit plaintext secrets; secret material lives encrypted under `sensitive/`.
- `m5pro` and `framework` are admin recipients on every `.sops.yaml` rule; server
  secrets also carry the owning host key. After changing recipients, run
  `just secret-refresh <path>`.
- Wire secrets through `config.sops.secrets.*.path` or `config.sops.placeholder.*`;
  set `owner`, `group`, `mode`, and `restartUnits` deliberately.

### Servers (lumo, worker)

Misconfiguration here affects reachability or trust boundaries. Read
`hosts/lumo/README.md` and `common/home-alpine/README.md` first.

- `lib/lab.nix` ripples through every service on every host.
- `scripts/alpine-bootstrap` controls root SSH, addresses, Tailscale, cgroups,
  kernel hardening, and nftables reachability. Mirror changes to
  `hosts/lumo/home/services/edge/nftables.nix` into it.
- Backends bind to loopback behind Traefik. Do not reintroduce blanket interface
  trust or wildcard listeners.
- No Nix-managed lumo service runs as root except rootful Podman (`podman.nix`).
- Container images are digest-pinned; bump digests deliberately. Never open a
  migrated usage-keeper v2 database with v1.
- `cliproxyapi.nix` touches auth and routing; quota reserves fail closed.
- Activation never runs `apk upgrade`; only `just <host>-upgrade apply` does.
- Keep Forgejo/Woodpecker disabled until the port 22 conflict is resolved.

### Pi and agent tooling

- Edit repo sources in `common/home-base/pi/`, not installed store links. Do not
  force-overwrite unmanaged extensions or install duplicates via `pi install`.
- Keep extension sibling directories together (agent-team imports ask-question).
- Observational Memory owns `session_before_compact`; `cache-safe-compaction`
  only observes `session_compact`.
- When bumping Pi or Observational Memory, regenerate the patch and re-run the
  upstream suite and type check against the pinned SDK.
- The managed launcher is not a sandbox; tools and workers run with normal host
  permissions (root on lumo).
- Skills under `common/home-base/agent-skills/` keep `SKILL.md` agent-neutral;
  Pi-specific mappings go in `workflows/pi.md` beside it.
- Do not manage generated system skills, sessions, memory data, auth state, or
  plugin caches from this repo.

### Other

- Framework: never run the destructive install path on a real host as validation;
  do not pin an end-of-life kernel series.
- TLS: preserve local/custom CA requirements; blacklist labels must exist in the
  target cacert version.
- Managed browser: use unique session names, close only owned sessions, never
  copy personal profiles or disable the browser sandbox (`pkgs/playwright-cli/README.md`).
- Temporary pins (Node.js, Bun canary) must be removed once upstream catches up;
  keep their regression tests.

## Code Style

### Formatting

- 2-space indentation, never tabs; `just fmt` enforces formatting.
- One blank line between major top-level bindings in large attrsets.
- Closing `}` and `]` align with the opening expression.

### Module shape

Returned attrsets start with `imports` when imports exist:

```nix
{ pkgs, dotfiles, ... }:
{
  imports = [ (dotfiles + /common/home-base) ./local-file.nix ];
  programs.foo.enable = true;
}
```

### Arguments, `inherit`, and `let`

- Inline short argument sets: `{ pkgs, ... }:`.
- For 3 or more arguments, one name per line with `...` last.
- Inline `inherit` for 1–2 names; vertical blocks for 3+.
- Use `let` only for reused values or to name an otherwise opaque expression.

### Lists, attrs, and naming

- Short lists on one line; longer lists one item per line.
- Align related assignments vertically when it improves readability.
- File and package names use `kebab-case`; Nix attribute keys use upstream casing
  (usually `camelCase`); preserve native external keys like `NSGlobalDomain`.
- Fish function module names match the function name.

### Data generation

- Prefer native Nix values over pre-serialized strings; generate JSON with `builtins.toJSON`.
- Build attrsets from lists with `builtins.listToAttrs` plus `map`.
- Auto-import with `builtins.readDir` plus filtering.
- Limit `with pkgs;` to clear package-list contexts.

### Packages and overlays

- New derivations live under `pkgs/<name>/default.nix` and are registered once in
  the matching `lib/flake/overlays/*.nix` file.
- Set `meta.mainProgram` and `meta.platforms`.
- Respect `runHook pre*` / `runHook post*` in custom phases.
- Use `lib.optionals` for platform-specific inputs; for platform-specific sources
  follow the `srcs.${stdenvNoCC.hostPlatform.system} or (throw ...)` pattern.

### Safety

- Fail clearly for unsupported platforms with `throw`.
- Reference executables in activation scripts by Nix store path, not ambient `PATH`.
- Keep comments sparse and useful.

## Documentation Scope

- `README.md`: concise, operator-facing overview.
- `AGENTS.md`: agent working rules, validation, guardrails. Not architecture.
- Subsystem detail goes next to the code (`hosts/<name>/README.md`,
  `pkgs/<name>/README.md`, `lib/flake/README.md`) or in `docs/` when cross-cutting.
- No other editor rule files (`.cursor/rules/`, `.cursorrules`,
  `.github/copilot-instructions.md`) exist; `AGENTS.md` is canonical.

## Commit Messages

Conventional Commits with this subject format:

```text
topic(machine/scope): subject
```

- `topic`: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `build`, `ci`, `chore`, …
- `machine`: affected host or layer, such as `m5pro`, `framework`, `lumo`, `common`, `pkgs`, or `repo`.
- `scope`: focused area, such as `home`, `niri`, `themegen`, `rime`, or `flake`.
- Keep `subject` short, imperative, and lowercase unless it contains proper nouns.

```text
feat(framework/niri): add workspace keybindings
fix(m5pro/default-apps): update browser associations
docs(repo/agents): document commit message format
```
