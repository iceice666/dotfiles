# dotfiles

Multi-host Nix configuration for `m5pro`, `framework`, `homolab`, `lumo`,
`worker`, and `gce-dns`.

One flake drives system configuration, Home Manager, secrets, wallpaper-derived theme generation, dev shells, and a small overlay of custom packages.

See `AGENTS.md` for detailed repo and editing guidance.

## Hosts

| Host | Flake output | Platform | Role |
| --- | --- | --- | --- |
| `m5pro` | `.#m5pro` | `aarch64-darwin` | personal macOS via `nix-darwin` + Home Manager |
| `framework` | `.#framework` | `x86_64-linux` | Framework laptop via NixOS + Home Manager |
| `homolab` | `.#homolab` | `x86_64-linux` | NixOS AI host |
| `lumo` | `.#homeConfigurations.lumo` | `aarch64-linux` | Alpine data/apps + edge Pi |
| `worker` | `.#homeConfigurations.worker` | `aarch64-linux` | Alpine disposable-work / agent-runtime Pi (ex-gateway); state lives on `lumo` |
| `gce-dns` | `.#gce-dns` | `x86_64-linux` | Google Compute Engine NixOS DoH resolver with Blocky |

## Layout

```text
flake.nix            # flake inputs and thin local framework entrypoint
Justfile             # thin task runner for build, switch, validation, secrets, maintenance
scripts/             # shell implementations for complex just recipes
treefmt.nix          # formatting (nixfmt + just)
assets/              # wallpapers and host images used by theme generation

common/              # shared modules applied to all hosts
  system/            # Lix, fonts, fish, allowUnfree for NixOS/nix-darwin hosts
  system-darwin/     # Darwin-specific system settings (experimental-features)
  system-nixos/      # NixOS-specific system settings (experimental-features)
  home-base/         # CLI baseline: git, direnv, fish, packages, starship, zoxide…
  home-alpine/       # root Home Manager baseline for Alpine + Lix hosts
  home-gui/          # GUI workstation: ghostty, vscodium, zed, rime, themegen…

hosts/               # per-host entrypoints
  m5pro/             # macOS; host.nix declares features, configuration/, home/, wallpaper.jpg
  framework/         # NixOS system + Home Manager modules; wallpaper.png
  homolab/           # NixOS server: configuration/, services/, home/, apps/, patches/, plan/
  lumo/              # Alpine root Home Manager + OpenRC data/apps + edge services
  worker/            # Alpine root Home Manager disposable-work / agent-runtime host (ex-gateway)
  gce-dns/           # Google Compute Engine image host for Blocky DoH

lib/                 # shared nix helpers and local flake framework
  flake/             # mk-host (feature-flag system), auto-discovery, HM wiring, overlays/
themegen/            # $HOME-relative theme templates rendered by Nix derivations
pkgs/                # custom overlay packages and the themegen Rust CLI
sensitive/           # sops-encrypted secrets, segregated under hosts/<name>/
```

Host output wiring is generated automatically: `lib/flake/hosts.nix` discovers every
`hosts/<name>/host.nix` at evaluation time — no hand-maintained list. Each spec declares
an attrset of feature flags; `mk-host.nix` injects the matching `common/` modules
and wires Home Manager accordingly.

**Adding a host:** create `hosts/<new>/host.nix` with feature flags. It appears as a
flake output automatically.

## Commands

```sh
just build           # dry-build current platform host
just switch          # apply configuration to current platform host
just boot            # set current NixOS host for next boot, Linux only
just fmt             # format all files
just fmt-check       # check Justfile formatting
just check           # format, Justfile metadata, and flake checks
just theme           # generate a local concrete theme cache for inspection
just theme-preview   # render and open this platform's wallpaper palette preview
```

`just` recipes are platform-gated: macOS maps to `m5pro`, and Linux detects the
hostname to pick `framework` or `homolab`. The same `build`, `switch`, and `boot`
recipe names have separate `[macos]` and `[linux]` implementations.


Homolab recipes run locally on the server itself (no remote deploy):

```sh
just homolab-build           # dry-build on the homolab
just homolab-switch          # build + activate on the homolab
just homolab-boot            # stage the closure for next boot
just homolab-gen-hardware    # refresh hardware-configuration.nix from the server
```

Lumo uses the official Alpine Linux 3.24 Raspberry Pi image with root-only Lix
(`--init none`). Its root Home Manager closure is built on the target and
activated through deploy-rs. Alpine owns boot, networking, OpenSSH, Tailscale,
cgroups, and the nftables launcher; Home Manager owns root tooling, Nix-built
service binaries, generated configuration, and lumo's OpenRC jobs (data/apps
plus the edge stack: Traefik, Authelia, Cloudflare DDNS).

```sh
just lumo-bootstrap lumo        # converge the existing Alpine/NVMe lumo host
just lumo-build                 # dry-activate root Home Manager
just lumo-switch                # deploy root Home Manager
just lumo-smoke                 # verify OpenRC services and local endpoints
```


Bootstrap prints the host age recipient. Add it to `.sops.yaml`, include it in
the matching host rule, then run `just secret-refresh sensitive/hosts/<host>`
before deploying services that require secrets.

GCE DNS image recipes build the `gce-dns` NixOS system and custom Google Compute
Engine image. The host runs Blocky as a DoH resolver and exposes its DoH and
Prometheus metrics listener over Tailscale TCP. Build these on `x86_64-linux` or
with a Linux builder.

```sh
just gce-dns-build    # dry-build the NixOS system toplevel
just gce-dns-image    # build the googleComputeImage artifact
just gce-dns-switch   # deploy over Tailscale after first boot
```

The first boot expects a GCE instance metadata attribute named
`tailscale-auth-key`. Use a preauthorized Tailscale auth key and ensure tailnet
ACLs allow `tailscale ssh iceice666@gce-dns`. The image does not enable public
OpenSSH or Google OS Login.

M5 Pro helper recipes are available only on macOS:

```sh
just m5pro-homebrew
just m5pro-activate
```

Framework activation:

```sh
git clone --recurse-submodules https://github.com/iceice666/dotfiles ~/dotfiles
cd ~/dotfiles
just build
just switch
```

After the first switch, use `just switch`.

NixOS owns the Framework system, including login/session launch, D-Bus,
PipeWire, NetworkManager, Bluetooth, polkit, greetd/ReGreet, and fingerprint
authentication for greetd and sudo. Home Manager is wired into the NixOS system
configuration for user-level programs, Niri, Eww, nirinit session persistence,
and dotfiles.

Enroll fingerprints with:

```sh
fprintd-enroll
```

Other:

```sh
just update
just update nixpkgs
just search <query>
just gc
just store-size
```

## Secrets

Encrypted with [`sops-nix`](https://github.com/Mic92/sops-nix). Rules in `.sops.yaml`.

```sh
just secret-encrypt sensitive/hosts/m5pro/forgejo.yaml ./forgejo.yaml
just secret-decrypt sensitive/hosts/m5pro/forgejo.yaml
just secret-edit sensitive/hosts/m5pro/forgejo.yaml
```

`m5pro` and `framework` are both admin recipients: every rule in `.sops.yaml`
includes both, so any secret can be read and edited from either workstation.
Server secrets additionally carry the owning host's key (`homolab`,
`homolab-home`, `lumo`, `worker`) so the host can decrypt at activation.
`framework` derives its age identity from `~/.ssh/id_ed25519` via
`SOPS_AGE_KEY_CMD` (see `common/home-base/default.nix`), so
`just secret-edit sensitive/hosts/lumo/<file>` works there with no extra setup.

After changing `.sops.yaml` recipients, refresh the existing secrets so their
recipient lists are rewritten in place:

```sh
# Run from a machine that holds one of the *current* recipient keys.
just secret-refresh sensitive/hosts/lumo
```

`just secret-refresh` takes a file or directory and walks it for
`.yaml`/`.yml`/`.json`/`.env`/`.ini`/`.key`/`.pem` files, running
`sops updatekeys --yes` on each. Pass no argument to refresh the whole
`sensitive/` tree. Files under `sensitive/hosts/homolab/` are still keyed to
`m5pro` only; re-key them from `m5pro` or the homolab itself when that host is
reachable.

Never commit plaintext secrets.

## Docs

- `AGENTS.md` — detailed repo structure, flake inputs, build matrix, code style, conventions.
- `common/home-gui/rime/README.md` — Frost/Rime data wiring and Traditional Chinese model setup.
- `common/home-gui/themegen/README.md` — wallpaper-driven theme generation pipeline.

## Acknowledgements

- [win_chan.jpg](./assets/win_chan.jpg): https://x.com/11359OC/status/2040280223632208281/photo/1
- [mzen.png](./assets/mzen.png): https://x.com/Drift0827/status/1990350670445306010
