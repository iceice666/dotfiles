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
3. Download each platform archive and compute the SRI sha256 hash. Use `scripts/prefetch-hashes` which downloads URLs sequentially and outputs `<url> <sri-hash>` pairs with unambiguous mapping. Fallback to `nix-prefetch-url <url>` for single URLs; never run multiple `nix-prefetch-url` calls in parallel.
   - **NEVER run parallel `nix-prefetch-url` calls**: Results arrive in completion order (fastest first), not dispatch order. Even parallel calls within a single package (across platforms) will scramble hash-to-URL mapping. Always prefetch sequentially — one URL at a time. Use timeouts of 300-600s for large files (DMGs, multi-100MB archives).
   - **Use build errors to correct hashes**: If you suspect a hash mapping error, run `nix build .#<name>` — the error message will show the correct hash for the URL.
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
  - Standalone packages: `nix build .#<name>` — works for most overlay packages on their supported platforms.
  - Some packages are not exposed as standalone flake outputs on all platforms (e.g. `zen-bin` on darwin uses the local `pkgs/zen-bin` package through the overlay but is not in `packages.aarch64-darwin`). For these, validate through a host build: `nix build .#darwinConfigurations.m3air.config.system.build.toplevel --dry-run` or the matching `just <host>-build` recipe.
  - Linux-only packages (`blocky-bin`, `cliproxyapi-bin`) cannot be built on darwin. Validate hashes through the build on a linux host, or accept that `nix-prefetch-url` is authoritative and document the gap.
- If validation cannot be completed, explain the blocker in the commit body or final response.

## Commit

- Inspect `git status` before editing and avoid including unrelated user changes.
- Commit only the changes you made.
- Prefer OMP's native `omp commit --dry-run` / `omp commit` flow when it can be constrained to agent-authored changes.
- Use a Conventional Commit subject in this repository's format, for example `chore(pkgs/flake): update custom package versions`.
