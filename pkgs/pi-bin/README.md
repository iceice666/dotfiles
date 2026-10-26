# Pi with managed TLS trust

The historical `pi-bin` attribute installs the upstream **npm distribution** of
Pi 1.4.0 under Node, not the standalone Bun executable. The standalone release
embeds an independent, outdated CA set; setting `SSL_CERT_FILE` did not remove
its trust in the compromised eMudhra chains in regression testing.

`package-lock.json` and `npmDepsHash` pin the npm graph. All Pi sibling packages
are overridden to 1.4.0 so a stray caret dependency cannot silently change the
SDK version (upstream pins them exactly since 1.3.0; the overrides stay as a
guard). Installation scripts are disabled. Linux clipboard prebuilds are
restricted to the host architecture and patched for Nix's `libxcb`.

The launcher selects OpenSSL verification and the explicit `dotfiles-cacert`
bundle, sets an empty certificate directory, and removes inherited additional
CA variables. The npm package root is
`libexec/pi/node_modules/@earendil-works/pi-coding-agent`; `PI_PACKAGE_DIR` points
there. Sessions, authentication and user settings remain unmanaged.

## Validation

```sh
nix build .#pi-bin
# Public probes; no API credentials or model requests are used.
NODE_OPTIONS="--import=$PWD/scripts/tls-trust-probe.mjs" ./result/bin/pi --version
```

The public probe exits before Pi starts. It requires a successful positive
control and certificate-verification errors for all twelve compromised chains;
DNS failures and timeouts are inconclusive failures, not evidence of safety.
The package's offline test verifies the four blocked root fingerprints and
local TLS acceptance/rejection. Install checks cover the version and SDK docs.

The shared managed extension suite remains in `common/home-base/pi/`.
Restart existing Pi processes after switching; a running process retains its
old runtime and TLS state.
