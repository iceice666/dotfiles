---
name: update-pkgs
description: Update custom Nix packages under pkgs/ to their latest upstream releases or revisions, compute new Nix hashes, validate builds, and commit the result.
globs:
  - "pkgs/**/*.nix"
  - "pkgs/**/Cargo.lock"
  - "pkgs/**/flake.nix"
---

# Update Packages

Update every custom package under `pkgs/` and any nested local package flakes to the latest upstream release or revision.

## Scope

- Review all `pkgs/*` derivations and local flakes such as `pkgs/kaguya-bin/flake.nix`.
- Update `version`, `tag`, `rev`, `hash`, `vendorHash`, `cargoHash`, and source URLs as needed.
- Update related lock files only when required by a local package flake.
- Do not update top-level flake inputs unless a custom package explicitly requires it.
- Do not touch plaintext secrets.

## Package update strategies

### GitHub release binaries (most packages)

Packages: `blocky-bin`, `cliproxyapi-bin`, `codex-cli-bin`, `default-browser`, `equibop-bin`, `oh-my-pi-bin`, `utiluti`, `zed-bin`, `zen-bin`.

For each:
1. Read `pkgs/<name>/default.nix` to extract `repo`, `version`, `tag_prefix`, and platform URLs.
2. Query the GitHub API for the latest release: `gh api /repos/<owner>/<repo>/releases/latest` (or scan releases for non-standard tag prefixes).
3. Download each platform archive and compute the SRI sha256 hash. Prefer `nix-prefetch-url <url>`; fallback to `curl | sha256sum | base64`.
4. Replace `version` and each `hash` in the `.nix` file.

### Source tarballs

Packages: `rime-frost`, `rime-octagram-zh-hant-essay-bgw`.

For each:
1. Check upstream tags or media URLs for the latest version.
2. `nix-prefetch-url <url>` to get the new hash.
3. Update `version` and `hash`.

### Local Rust packages

Packages: `appearance-scheduler`, `framework-eww-state`, `themegen`.

For each:
1. Check `Cargo.toml` and `Cargo.lock` for dependency or version changes.
2. If the package version changed, update `version` in `default.nix`.
3. If `Cargo.lock` changed, update the `cargoLock.lockFile` reference (or `cargoHash` if applicable). Let `nix build` tell you the expected hash.

### Local flakes

Packages: `kaguya-bin`.

1. Check `flake.nix` inputs for updates.
2. Run `nix flake lock --update-input <input>` inside `pkgs/kaguya-bin/` if an input should advance.
3. Verify the flake still evaluates with `nix build .#kaguya-bin` or through the framework host.

## Validation

- Run `just fmt` after editing.
- Run the narrowest relevant build or check that validates the changed packages:
  - Standalone packages: `nix build .#<name>`
  - If the package has no standalone flake output, validate through an owning host build as described in `AGENTS.md`.
- If validation cannot be completed, explain the blocker in the commit body or final response.

## Commit

- Inspect `git status` before editing and avoid including unrelated user changes.
- Commit only the changes you made.
- Prefer OMP's native `omp commit --dry-run` / `omp commit` flow when it can be constrained to agent-authored changes.
- Use a Conventional Commit subject in this repository's format, for example `chore(pkgs/flake): update custom package versions`.
