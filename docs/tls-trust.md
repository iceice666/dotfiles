# TLS trust and runtime security pins

Background for the October 2026 eMudhra incident response and the temporary
runtime pins that came with it.

## CA distrust

`lib/tls-ca-blacklist.nix` is a function of the cacert version returning the
NSS labels to remove. cacert's blacklist fails the build for labels missing from
the store, and NSS 3.131.1 (nixpkgs-unstable) already drops the three emSign
roots while nixos-26.05 still ships 3.126 with them, so the emSign labels are
listed only below 3.131; `pkgs/pi-bin/trust.test.cjs` asserts all four
fingerprints are absent either way.

- `common/system` applies the list to NixOS/nix-darwin.
- `dotfiles-cacert` in the shared overlay supplies an explicit plain bundle for
  Pi, CLI session variables, and configured containers without rebuilding every
  package in nixpkgs. Session variables apply to new sessions, not every daemon
  or application's embedded store.
- Alpine activation installs the full APK `ca-certificates` package if missing,
  records disabled source entries, and regenerates its bundle without discarding
  local certificates. It does not upgrade APK packages on every activation.
- macOS activation runs `scripts/tls-trust-macos.py`: it backs up the native
  `/etc/ssl/cert.pem` once, adds System keychain deny entries from the four
  fingerprint-verified public PEMs in `common/system-darwin/tls-distrust-roots.pem`,
  and atomically filters the native PEM bundle. It requires interactive operator
  privilege when sudo is unavailable. `--check` only inspects PEM membership, not
  keychain state or every application verifier.

Preserve local/custom CA requirements deliberately when changing these paths.

## Node.js

The shared overlay (`lib/flake/overlays/nodejs.nix`) updates both
`nodejs-slim_22`/`nodejs-slim_24` and their npm/corepack wrappers, including the
default `nodejs` alias. Updating only `home.packages` does not update absolute
runtime paths embedded in Pi, Playwright, or Bitwarden. Packaging, launcher CA
defaults, limits and validation commands are in `pkgs/nodejs-bin/README.md`.

Restart existing Node/Pi processes after activation; old generations and running
processes retain their old runtimes. Updating host Node does not patch Electron
applications, user-managed fnm installations, or container images (lumo's Umami
and usage-keeper images are separate boundaries, see `hosts/lumo/README.md`).

## Bun

Bun is temporarily pinned (`lib/flake/overlays/global-patches.nix`) to the
official patched `1.4.4-canary.1+963452075` assets with fixed hashes, explicitly
approved by the operator. The canary URL is rolling: replacement causes a hash
failure, never a silent update. Replace this exception with a verified fixed
stable release when available. Pi instead uses its supported npm/Node
distribution at the same SDK version; updating external Bun cannot update an
already compiled standalone Pi.

## Validation

```sh
python3 scripts/tests/test-alpine-trust.py
python3 scripts/tests/test-tls-trust-macos.py
```

These are non-destructive fixtures. `scripts/tls-trust-probe.mjs` tests a
positive control and all twelve public compromised-chain endpoints; it never
authenticates. Require certificate errors, not generic connection failures.
Existing processes must be restarted after activation.

Managed browser profiles need separate fresh-process verification: Playwright
disables component updates by default, and pre-seeded CRLSets load
asynchronously, so a successful CLI probe does not establish browser safety.
Do not use an unverified managed browser for sensitive browsing.
