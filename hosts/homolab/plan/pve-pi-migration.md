# Proxmox VE + Raspberry Pi Gateway Migration Plan

## Goal

Split the single x86_64 NixOS `homolab` box into:

- A **Raspberry Pi edge appliance** (always-on, low-power, survives the big box
  being down): DNS + ingress + auth + mesh.
- A **Proxmox VE host** (the repurposed GPU box) running NixOS **LXC/VM guests**
  for data, apps, and AI — with the **database on its own disk**.

This is the structural next step for the other in-flight plans here:
`komodo-ferretdb-authelia.md` needs a real DB-with-disk, and
`woodpecker-ci-vm-isolation.md` wants a VM boundary that a hypervisor provides
cleanly.

## Target Architecture

```
Internet ──▶ Router (WAN/NAT/DHCP)  ──80/443 port-forward──▶  Pi
                     │ LAN 192.168.1.0/24                      │
   ┌─────────────────┼──────────────────────────┬─────────────┘
   │                 │                           │
[ Pi: gateway ]   [ PVE host (ex-GPU box) ]──────┴── NixOS guests:
 aarch64 NixOS      x86_64 Proxmox VE            ┌── db   (LXC)  → dedicated disk
 USB-SSD boot                                    ├── apps (LXC)
                                                 └── ai   (VM, GPU passthrough)
```

| Node | Type | Arch | Services (from current homolab) |
|------|------|------|---------------------------------|
| **gateway** (Pi) | bare metal | aarch64 | Traefik (80/443, TLS), Authelia (local SQLite), Technitium DNS (53), Tailscale (subnet-router/exit), Cloudflare DDNS + IP-set refresh, OpenSSH |
| **db** | PVE **LXC** | x86_64 | PostgreSQL 17 (own disk at data dir), Valkey |
| **apps** | PVE **LXC** | x86_64 | OmniRoute, Dynacat, dev-port-proxy, Prometheus, Grafana, Podman, daily-audit; future: Komodo/FerretDB |
| **ai** | PVE **VM** | x86_64 | Llama-Swap + NVIDIA GPU passthrough + `/mnt/storage/models` disk |

The Pi's Traefik proxies every public domain (`*.justaslime.dev`) to the
appropriate guest over the LAN; Authelia forward-auth still gates the protected
routes exactly as today.

## Decisions

Locked during planning (2026-05-30):

1. **Pi = edge appliance + Tailscale subnet-router/exit-node**, behind the
   existing router. The router keeps WAN/NAT/DHCP; its 80/443 port-forward
   repoints from the old box to the Pi. The Pi is *not* a WAN router.
2. **PVE host = the repurposed GPU box.** This is a **cutover, not parallel** —
   old NixOS `homolab` and Proxmox cannot share the hardware, so the Pi stands
   up first while the old box still serves, then the box is wiped to PVE.
3. **Internal transport = LAN (ideally a dedicated VLAN), firewall-scoped.**
   Each guest binds its service to its LAN IP; its firewall accepts only the
   Pi's IP on that port. Tailscale is reserved for remote admin + subnet routing.
4. **Consolidated guests** (~3): one DB LXC, one apps LXC, one AI VM.

Recommend-with-default (confirm during execution):

- **AI = passthrough VM, not LXC.** A NixOS LXC would have to match the PVE host
  kernel's NVIDIA driver version; a VM with PCIe passthrough owns the GPU cleanly
  and keeps the guest a normal NixOS image.
- **Authelia storage = local SQLite + local sessions on the Pi.** Decouples the
  always-on gateway (DNS+auth+ingress) from PVE uptime. The central DB then
  serves app workloads only (Komodo/FerretDB, future), which is what "DB on its
  own disk" is really for.

## Why This Direction

- Separates the always-on, low-power control plane (DNS/auth/ingress/mesh) from
  the heavy, occasionally-down compute plane (DB/apps/GPU).
- Keeps DNS resolving and the auth portal reachable even when the PVE box is off
  or rebuilding — a property the current monolith cannot offer.
- Gives the database a dedicated disk and the GPU a clean passthrough boundary.
- Reuses almost every existing service module; the split is about *placement*
  and *transport*, not rewrites.

## Internal Security Model (the key translation)

The current crown jewel — *loopback-only + explicit `DROP`* on one host
(`hosts/homolab/configuration/networking.nix`) — cannot survive a multi-host
split. It is replaced, not abandoned:

- Each guest service binds to its **LAN IP** (not `0.0.0.0`, not `127.0.0.1`).
- Each guest firewall **accepts only the Pi's IP** on each service port — mirror
  the existing per-port `iptables`/ipset helpers, swapping "loopback DROP" for
  "accept Pi, drop rest".
- Put guests + Pi on a **dedicated VLAN/bridge** if the switch allows, so
  inter-service traffic never touches the general LAN.
- **Postgres flips from unix-socket/peer-auth to TCP + scram + TLS**, scoped to
  the apps guest IP (today it is socket-only, `enableTCPIP = false`,
  `hosts/homolab/services/dev/database.nix`). Authelia's old peer-auth PG user
  goes away (it moves to local SQLite).
- Cloudflare ip-set logic + DDNS move to the Pi alongside Traefik (they exist to
  scope 80/443 to Cloudflare, which now terminates at the Pi).

## Repo Structure Changes

New host trees, each mirroring the existing `hosts/<name>/configuration` +
`home` shape (see the framework/homolab pattern in `flake.nix`):

```
hosts/
  gateway/   # aarch64 NixOS Pi — moved edge/* modules, retuned networking
  db/        # LXC — services/dev/database.nix split out, dedicated-disk mount
  apps/      # LXC — services/ai/omniroute.nix, edge/dynacat, edge/dev-port-proxy,
             #       edge/monitoring, dev/podman, services/audit.nix
  ai/        # VM  — services/ai/llama-swap.nix + GPU passthrough config
  homolab/   # decomposed; tree retired once guests are live
```

Most existing service `.nix` modules **move nearly verbatim** — the change is
*which host imports them* plus the bind-address/firewall retune above.

`lib/homolab.nix` → generalize into a **whole-topology** lib (keep the file name
or rename to `lib/homelab.nix`): add a `hosts.<name>.lan` IP map and `role`
alongside the existing ports/domains/contact. Traefik on the Pi then computes
backends as `http://${lib.hosts.apps.lan}:${lib.ports.grafana}` instead of
`127.0.0.1`, and each guest reads its own identity from the same source. This is
the single most important DRY move for the split.

`flake.nix`:

- Add `system = "aarch64-linux"` `nixosConfigurations.gateway`; add x86_64
  `nixosConfigurations.{db,apps,ai}`, all by analogy to the existing `homolab`
  block (same `specialArgs`/overlay/sops/home-manager modules).
- Add matching `deploy.nodes.*` (sshUser `iceice666`, `remoteBuild = true`,
  `activate.nixos`); the gateway node uses the aarch64 activation lib.
- `checks` already validates `self.deploy`; extend to aarch64 if needed.

## Build & Deploy Notes (the practical sharp edges)

- **Pi: boot from USB-SSD, not microSD.** Technitium zones + Authelia SQLite +
  ACME state are write-heavy and will chew through an SD card.
- **aarch64 builds**: the Pi is too weak to `remoteBuild` the custom derivations
  (Technitium is a from-source .NET build). Options, recommend (a):
  (a) an **x86 NixOS guest as aarch64 builder** via
  `boot.binfmt.emulatedSystems = [ "aarch64-linux" ]`, push closures to the Pi;
  (b) rely on `cache.nixos.org` for stock pkgs + remote-build only the customs.
  Decide before the first deploy.
- **NixOS-in-Proxmox**: build LXC root tarballs with
  `nixos-generators -f proxmox-lxc` (guest sets `virtualisation.proxmoxLXC`),
  import as a PVE template, create the container, then manage updates via
  deploy-rs over SSH — same loop as homolab today. The AI VM is a normal NixOS
  install with `vfio-pci` GPU passthrough configured on the PVE host.
- **DB own disk**: dedicate a PVE disk (zvol/LVM-thin volume, or a passed-through
  physical disk) and mount it at the Postgres data dir in the db LXC.
- **Secrets**: each new host gets its own age key; re-encrypt the relevant
  `sensitive/hosts/<host>/*` to include it (today they are encrypted to homolab +
  m3air — `hosts/homolab/configuration/sensitive/`). Split secrets to follow
  their service to the new host.
- **DNS SPOF**: the Pi becomes the LAN's only resolver. Keep it minimal/reliable
  and set a secondary resolver (e.g. `1.1.1.1`) on the router/DHCP so a Pi reboot
  does not black out the LAN.

## Phased Cutover (no big-bang)

### Phase 0: Prep

1. Provision the Pi (Pi 4/5 + USB-SSD), generate its age key.
2. Stand up the aarch64 builder (x86 NixOS guest with `boot.binfmt`).
3. Write `hosts/gateway`; re-encrypt gateway secrets.

### Phase 1: Stand up the Pi while old homolab still runs

1. Bring up Technitium (point a couple of LAN clients at it to validate),
   Tailscale, Traefik, Authelia.
2. Have the Pi's Traefik proxy back to the *still-running old box* for off-Pi
   backends (`homolab.network.lan.address`).
3. Repoint the router's 80/443 forward to the Pi; validate external + internal
   routing through the Pi.

### Phase 2: Cutover the box

1. Back up `/mnt/storage` (models, omniroute data) + a Postgres dump.
2. Wipe the GPU box; install Proxmox VE.
3. Create the dedicated DB disk + GPU passthrough (`vfio-pci`).

### Phase 3: Build guests

1. db LXC: restore the PG dump onto the dedicated disk; bring up Valkey.
2. apps LXC: restore omniroute data; bring up OmniRoute/Dynacat/dev-proxy/
   monitoring/podman/audit.
3. ai VM: GPU passthrough + restore models.
4. Repoint the Pi's Traefik backends from the old box to the new guest IPs.

### Phase 4: Finalize

1. End-to-end validation (see below).
2. Retire `hosts/homolab`.
3. Update `AGENTS.md`/`README`/`lib` to describe the new topology.

## Validation Checklist

- `just check` (flake eval, treefmt) green after flake wiring lands.
- Per-host dry build before each activation: `deploy .#<host> --dry-activate`
  (aarch64 gateway built via the emulated builder).
- DNS: query Technitium on the Pi from a LAN client; `dns.justaslime.dev` UI
  loads through Traefik with 2FA.
- Ingress: each `*.justaslime.dev` resolves → Pi Traefik → correct guest;
  Authelia forward-auth gates the protected ones; external hit via Cloudflare.
- DB: an app workload connects over TCP+TLS scoped to its IP; confirm Postgres
  data really lives on the dedicated disk (`findmnt` of the data dir).
- AI: OpenAI-compatible smoke check against the ai VM endpoint; `nvidia-smi`
  inside the VM shows the passed-through GPU.
- Gateway autonomy: power off PVE → DNS + the Authelia login portal still work.

## Risks and Caveats

- The cutover is destructive to the old box: a tested backup/restore of
  `/mnt/storage` and the Postgres dump is mandatory before wiping.
- aarch64 build path must exist before the first real gateway deploy, or
  Technitium's .NET build will stall on the Pi.
- Putting the only LAN resolver on the Pi is a DNS SPOF; mitigate with a
  secondary resolver and a minimal, reliable Pi config.
- `unstablePkgsFor` sets `cudaSupport = true` for aarch64 too; harmless for the
  CUDA-free gateway closure, but a future CUDA-conditional edge dep would bite at
  build time on the Pi (invisible to eval).
- VLAN feasibility depends on the switch; if untagged-LAN-only, the
  firewall-scoping (accept Pi IP only) still holds, just without VLAN isolation.

## Open Flags

- Postgres currently has **only Authelia** as a consumer; moving Authelia to
  local SQLite makes the dedicated-disk DB initially **forward-looking**
  (Komodo/FerretDB per `komodo-ferretdb-authelia.md`). Confirm that is the intent
  vs. also moving OmniRoute/other state into central PG.
- Woodpecker CI, when added, is the one workload that justifies *its own VM*
  (per `woodpecker-ci-vm-isolation.md`) rather than the apps LXC.

## Follow-Up Implementation Tasks

1. Generalize `lib/homolab.nix` into a whole-topology lib.
2. Migrate the edge service modules onto `hosts/gateway` (Traefik, Authelia →
   SQLite, Technitium, Cloudflare DDNS/IPs).
3. Add `nixosConfigurations.{db,apps,ai}` + deploy nodes.
4. Stand up the aarch64 emulated builder.
5. Provision PVE: DB disk, GPU passthrough, LXC templates.
6. Execute the phased cutover with tested backups.

## Recommendation Summary

Build the Pi edge gateway first, alongside the still-running homolab, with its
Traefik proxying back to the old box during bring-up. Only then cut the GPU box
over to Proxmox VE and rebuild the data/apps/AI workloads as consolidated NixOS
guests, giving the database its own disk and the GPU a passthrough VM. Keep the
gateway minimal so DNS and auth survive PVE downtime.
# Historical Note

The Raspberry Pi NixOS image portions of this design are superseded by the
Alpine 3.24, Lix, standalone root Home Manager, and OpenRC deployment for
`gateway` and `lumo`.
