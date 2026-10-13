# Personal Ghostty fork (macOS)

The overlay exposes `pkgs.ghostty` on both platforms:

- Linux uses the pinned `iceice666/ghostty` flake's ReleaseFast package.
- Apple Silicon macOS uses this fixed-hash release ZIP. The upstream fork flake
  does not provide the macOS application bundle.

Current source: `905108bca070c450a2ad25d25011f2746498efd8`.
[Release](https://github.com/iceice666/ghostty/releases/tag/fork-905108bca070)
contains the ZIP, SHA-256, and build manifest. Built with Xcode 26.6 and Zig 0.16.0,
`zig build -Doptimize=ReleaseFast -Dxcframework-target=native` on arm64.
The fork checkout has a local `scripts/release-macos-local.sh` packaging helper;
that uncommitted helper is not included in the pinned source revision.

The app is ad-hoc signed, **not Developer ID signed or notarized**. Gatekeeper may
require manual approval on first launch. Automatic upstream update checks are
turned off so this fork is not silently replaced. Nix fixup is disabled to preserve
the bundle's signature; verify it with `codesign --verify --deep --strict`.

For updates, build and verify a new source revision, publish a distinct release
asset (do not replace this pinned ZIP), then update the source input, version,
URL, and hash together. Intel macOS is not currently packaged.

Validation:

```sh
nix build .#ghostty
just build
just check
```
