# PVE + Pi Migration — Handoff

Companion to `pve-pi-migration.md`. This is the live status: what is built, what
is validated, and how to pick the work back up. Execution order is **Pi host
first** — the gateway is built alongside the still-running `homolab` box.

## Status at handoff (2026-05-30)

Step 1 of the gateway track is done: the `hosts/gateway/` (Pi, aarch64) tree is
scaffolded and wired into the flake. Nothing else has been touched —
`hosts/homolab/` is untouched and still the primary host.

**Validated (eval only — there is no aarch64 hardware/builder yet):**

- All gateway Nix files parse (`nix-instantiate --parse`).
- `nix fmt` reports 0 changes (style matches treefmt).
- `nix eval .#nixosConfigurations.gateway.config.system.build.toplevel.drvPath`
  produces a derivation — the full module tree type-checks, every `homolab` lib
  reference resolves, no option conflicts.
- `nix eval .#checks.x86_64-linux --apply builtins.attrNames` evaluates, so the
  new aarch64 `deploy.nodes.gateway` node is schema-valid.

**Not validated (cannot be, without the Pi):** any actual build/activation. The
`hardware-configuration.nix` is a deliberate placeholder.

## What step 1 delivered

| File | Notes |
|------|-------|
| `hosts/gateway/configuration/default.nix` | host entrypoint, lean package set; `./sensitive` import left commented until the Pi age key exists |
| `hosts/gateway/configuration/system.nix` | aarch64, extlinux boot (placeholder), kernel hardening carried from homolab; CUDA substituter intentionally dropped |
| `hosts/gateway/configuration/networking.nix` | gateway firewall — DNS/SSH LAN-only, 80/443 LAN+Cloudflare, on-Pi UIs (Authelia/Technitium) loopback-only |
| `hosts/gateway/configuration/user.nix` | mirrors homolab user + home-manager wiring |
| `hosts/gateway/configuration/hardware-configuration.nix` | **placeholder** — regenerate on the board |
| `hosts/gateway/home/default.nix` | minimal headless home |
| `hosts/gateway/services/edge/{openssh,tailscale}.nix` | live; Tailscale set to subnet-router + exit-node |
| `hosts/gateway/services/edge/default.nix` | TODO imports for traefik/authelia/technitium/cloudflare |
| `flake.nix` | `nixosConfigurations.gateway` (aarch64) + `deploy.nodes.gateway` |

## Placeholders to fill on the real Pi

All flagged with `TODO(hardware)` in-file:

- `networking.nix`: NIC name (`end0`) and static LAN IP (`192.168.1.2`) — must
  differ from the old box's `192.168.1.127` so both can run during cutover.
- `hardware-configuration.nix`: regenerate via `nixos-generate-config
  --show-hardware-config` on the booted Pi (mirror `just homolab-gen-hardware`).
- `system.nix`: bootloader + `boot.kernelPackages` for the actual Pi model.

## Remaining gateway steps

2. **Migrate edge services onto the Pi.** Bring Traefik, Authelia (→ local
   SQLite + local sessions), Technitium, and the Cloudflare DDNS/IP-set glue over
   from `hosts/homolab/services/edge/`, then uncomment them in
   `hosts/gateway/services/edge/default.nix`. Retune Traefik backends to
   `homolab.network.lan.address` (old box) for bring-up; flip to per-guest IPs in
   Phase 3. **Caveat:** `tailscale.nix` sets `permitCertUid = "traefik"`, which
   presumes the `traefik` user from this step — do not `deploy .#gateway`
   standalone before Traefik lands.
3. **aarch64 build path.** Stand up the x86 NixOS aarch64 builder
   (`boot.binfmt.emulatedSystems`) and flip `deploy.nodes.gateway.remoteBuild` to
   `false`, or accept slow on-Pi builds.
4. **Provision + validate.** Flash USB-SSD, regenerate hardware config, set the
   real IP/interface, re-encrypt gateway secrets, `deploy .#gateway`.

Then proceed to the PVE-host track (db/apps/ai guests) per `pve-pi-migration.md`
Phases 2–4.

## How to resume (commands)

```sh
# eval-check the gateway after edits (no build; works from any platform)
nix eval --raw .#nixosConfigurations.gateway.config.system.build.toplevel.drvPath

# once the Pi exists and the builder is up
deploy .#gateway --dry-activate
deploy .#gateway
```

Note: `nix` flake eval only sees git-tracked files, so `git add` new files before
evaluating.

## Cross-references

- Full design: `pve-pi-migration.md`
- DB-with-disk consumer: `komodo-ferretdb-authelia.md`
- CI VM (own-VM exception to consolidation): `woodpecker-ci-vm-isolation.md`
# Historical Note

This NixOS image-based gateway handoff is superseded by the Alpine 3.24, Lix,
standalone root Home Manager, and OpenRC deployment under `hosts/gateway/`.
