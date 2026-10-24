# Official Node.js security binaries

The shared overlay selects official Node 24.22.1 and 22.23.4 binaries for native
Linux/macOS x86_64 and arm64. Source and platform archives are pinned by SHA-256
from `https://nodejs.org/dist/v<VERSION>/SHASUMS256.txt`. Linux ELF interpreters
and C++ library paths are adapted with autoPatchelf; V8 is never compiled.
`patchelfFlags = [ "--no-sort" ]` preserves ELF ordering: ordinary rewriting
reproducibly made ARM64 Node crash at startup. Regression tests also execute
`process.execPath` directly to catch relocation failures.

Full matching source remains `src` for Nix's `srcOnly`/node-gyp contract. The
installed npm comes from this source with nixpkgs' offline-build and Darwin
node-gyp patches. Corepack is retained without pnpm/yarn download shims (which
would shadow Nix's offline package managers); the binary archive supplies headers.
There are deliberately no `libv8` or V8 compiler-generator outputs. Cross builds
are rejected. Consumers requiring these source-build outputs need a separate
source package, not fabricated binary compatibility.

`bin/node` wraps the official binary in `libexec/node`, defaults `NODE_OPTIONS`
to `--use-openssl-ca`, and supplies the filtered CA file and an empty certificate
directory if the caller did not select its own. These are overridable defaults,
not a sandbox or universal certificate policy. `process.execPath` is the raw
binary: children normally inherit the defaults, but a cleared environment loses
them. Pi's own wrapper explicitly selects its filtered CA bundle as before.

## Validation

From the repository root:

```sh
nix build --no-link .#nixosConfigurations.framework.pkgs.nodejs_24 \
  .#nixosConfigurations.framework.pkgs.nodejs_22
nix build --no-link .#nixosConfigurations.framework.pkgs.nodejs_24.tests.nativeAddon \
  .#nixosConfigurations.framework.pkgs.nodejs_22.tests.nativeAddon
nix build --no-link .#nixosConfigurations.framework.pkgs.pi-bin \
  .#nixosConfigurations.framework.pkgs.playwright-cli
just fmt
just check
```

Each runtime's install check executes `scripts/tests/test-nodejs-security.mjs`,
npm, and corepack. Native-addon tests compile and load a dependency-free N-API
module using patched npm/node-gyp and `srcOnly nodejs`, offline. Pi checks local
TLS acceptance/rejection; Playwright checks its extraction fixtures. macOS and
ARM must be validated natively before being reported as deployed.

A global runtime replacement also changes packages using Node at build time,
including Chromium. `common/home-base/browser.nix` selects Chromium from a
pristine import of the same locked nixpkgs to retain its binary cache; the
Playwright CLI still uses patched Node. Other build-time consumers may still
require expensive rebuilds even though Node itself is now precompiled. Host activation still requires a complete successful build;
existing processes and old generations retain old runtimes until restarted or
retired. Container and Electron runtimes are separate boundaries.
