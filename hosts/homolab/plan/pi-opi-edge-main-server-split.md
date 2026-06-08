# Raspberry Pi 5 And Orange Pi 5 Pro Service Split Plan

## Goal

Move nearly all always-on services off the current desktop machine into two low-power ARM hosts:

- Raspberry Pi 5 4GB with 64GB SD card as the edge gateway and network control point.
- Orange Pi 5 Pro with 1TB NVMe as the main always-on server.
- Current desktop remains an on-demand GPU and compute-heavy worker, started through Wake-on-LAN when needed.

The intended result is a quieter, lower-power homelab where normal services stay available without keeping the desktop awake.

## Hardware Roles

### Raspberry Pi 5

Primary role: edge gateway.

Good fit for:

- Reverse proxy ingress, such as Traefik, Caddy, or nginx.
- Tailscale, WireGuard, or SSH bastion access.
- LAN DNS and resolver services, such as AdGuard Home, dnsmasq, or Unbound.
- ACME certificate issuance and renewal.
- Lightweight service health endpoints.
- Wake-on-LAN triggers for the desktop.
- Small control-plane services that can tolerate brief downtime.

Avoid on the Raspberry Pi 5 unless storage is moved off SD card:

- Databases.
- Chatty application logs.
- Container volumes with frequent writes.
- Media libraries.
- Backup targets.
- Anything where SD card corruption would be painful.

### Orange Pi 5 Pro

Primary role: main server.

Good fit for:

- Persistent service containers.
- PostgreSQL, Valkey, SQLite-backed applications, and other stateful services.
- Forgejo, Vaultwarden, Immich, Paperless, Nextcloud, or similar user-facing services.
- Internal APIs and application backends.
- Observability, metrics, and log storage.
- File sync, backup staging, and other NVMe-backed data services.
- Lightweight local AI routing or proxy services that do not need a desktop GPU.

The 1TB NVMe makes this the correct host for service state. It should be the default destination for anything with persistent data.

### Desktop

Primary role: on-demand compute node.

Good fit for:

- GPU-heavy LLM inference.
- CUDA, ROCm, or other accelerator workloads.
- Large builds.
- Media transcoding when GPU acceleration is required.
- Burst compute jobs that do not justify keeping the desktop on all day.

The desktop should not be a hard dependency for normal home services. Services that use it should degrade gracefully, queue work, or show an explicit unavailable state while it is asleep.

## Target Architecture

```text
GCE DNS fallback
    |
Internet / Tailnet / LAN
    |
Raspberry Pi 5
edge gateway, DNS, reverse proxy, VPN, WOL, health
    |
Orange Pi 5 Pro
main server, containers, databases, storage, observability
    |
Desktop
sleeping GPU and compute worker
```

The Raspberry Pi owns the front door. The Orange Pi owns application state. The desktop is only awakened for jobs that need its GPU or larger compute budget.
The existing GCE DNS host stays useful as offsite DNS fallback and as an
external monitoring point, but it should not be the source of truth for the
home network.

## Proposed Host Names

Use explicit host roles rather than overloading `homolab` as a single machine:

| Role | Proposed host | Main responsibility |
|---|---|---|
| Edge gateway | `edge-rpi5` | LAN edge, DNS, reverse proxy, Tailscale, WOL |
| Main server | `opi5-main` | Persistent services, databases, storage, observability |
| Worker | `desktop-worker` | GPU, builds, transcoding, burst compute |
| Offsite DNS | `gce-dns` | DoH fallback, external DNS health, remote probe point |

The old `homolab` name can remain as a service concept during migration, but
new Nix host outputs should use names that describe the physical roles.

## Fixed Decisions

- Treat the Raspberry Pi 5 SD card as disposable or mostly stateless.
- Put persistent service data on the Orange Pi 5 Pro NVMe.
- Keep normal user-facing services available while the desktop is asleep.
- Use Wake-on-LAN to start the desktop from either the Raspberry Pi or Orange Pi.
- Keep the Orange Pi reachable directly over LAN even if the Raspberry Pi gateway is down.
- Back up Orange Pi NVMe data to a separate target. NVMe is primary storage, not a backup.
- Validate Orange Pi 5 Pro NixOS support before migrating critical services.
- Keep GCE DNS as a fallback resolver and external metrics target.
- Put observability storage on the Orange Pi, not on the Raspberry Pi SD card.
- Prefer explicit degradation for desktop-backed services over hidden automatic wakeups.
- Keep secret material in `sops`; never back up plaintext secret exports.

## Service Placement

### Edge Gateway Services

Candidate services for the Raspberry Pi 5:

- Traefik edge routes.
- ACME certificate management.
- Tailscale entrypoint and primary subnet routing.
- LAN DNS, ideally using the same Blocky style already used by `gce-dns`.
- SSH bastion.
- Wake-on-LAN helper.
- Lightweight uptime checks.

The Raspberry Pi should forward most application traffic to the Orange Pi. It should not own application databases or large runtime state.

Recommended edge routes:

| Public/internal name | Upstream |
|---|---|
| `auth.justaslime.dev` | Orange Pi Authelia |
| `grafana.justaslime.dev` | Orange Pi Grafana |
| `traefik.justaslime.dev` | Raspberry Pi Traefik dashboard |
| `home.justaslime.dev` | Orange Pi dashboard |
| `omniroute.justaslime.dev` | Orange Pi routing frontend/API |
| `dns.justaslime.dev` | Raspberry Pi Blocky DoH, with GCE as fallback |

The Raspberry Pi should expose only the small set of edge ports needed for
ingress and management. Everything else should stay on LAN or Tailscale.

### Main Server Services

Candidate services for the Orange Pi 5 Pro:

- Podman or Docker runtime.
- PostgreSQL.
- Valkey or Redis.
- Forgejo or Gitea.
- Vaultwarden.
- Immich.
- Paperless.
- Nextcloud or file-sync services.
- Internal dashboards.
- Monitoring and log storage.
- OpenAI-compatible routing for lightweight model providers or remote workers.
- Backup staging and restore testing.
- Configuration-driven service discovery for the dashboard and monitoring stack.

Services currently running on the desktop should move here unless they require the desktop GPU or high sustained compute.

Recommended storage layout:

```text
/mnt/storage/
  app/
    authelia/
    forgejo/
    vaultwarden/
    paperless/
    immich/
  database/
    postgresql/
    valkey/
  observability/
    prometheus/
    loki/
    grafana/
  backup/
    postgres-dumps/
    restic-cache/
    restore-tests/
  podman/
```

Use the exact paths only after the Orange Pi disk layout is decided. The
important part is separating service state, database state, observability
state, and backup staging.

### Desktop Worker Services

Candidate desktop-only workloads:

- Local LLM backends that require the desktop GPU.
- Build workers.
- Transcoding workers.
- Batch jobs.
- Large code or document processing tasks.

The Orange Pi can act as the stable API endpoint and route to the desktop only when it is awake.

Recommended worker contract:

- Orange Pi owns the stable service URL.
- Orange Pi checks desktop health before routing.
- Wake-on-LAN is triggered only by explicit actions or services that are designed for it.
- If the desktop is asleep, dashboards and APIs should report `worker asleep` or `worker unavailable`.
- Desktop services should register readiness after boot before they receive traffic.

## DNS And Remote Access

Use a layered DNS model:

| Layer | Owner | Purpose |
|---|---|---|
| LAN DNS | Raspberry Pi | Normal home devices and local records |
| Tailnet DNS | Tailscale | Remote access to LAN and service names |
| Offsite DoH | GCE DNS | Fallback resolver and external health target |
| Service DNS | Cloudflare or current DNS provider | Public names routed to the home edge |

Recommended behavior:

- Raspberry Pi is the primary LAN resolver.
- GCE DNS stays online as an offsite fallback, especially for mobile or remote devices.
- Orange Pi service names resolve to the Raspberry Pi edge unless the route is explicitly LAN-only.
- Internal-only services should be reachable over LAN and Tailscale without public exposure.
- The Raspberry Pi can advertise the LAN subnet through Tailscale.
- The Orange Pi can later become a backup subnet router if failover is worth the extra complexity.

## Backup Design

The Orange Pi NVMe is primary storage, not backup storage. Use backups for
recoverability from deletion, corruption, failed migration, and board/storage
loss.

Recommended first backup target:

```text
Orange Pi NVMe
  -> local dump/snapshot staging
  -> restic encrypted repository
  -> rclone transport
  -> Google Drive
```

Google Drive is a reasonable first remote target because 5TB is already
available. Use restic encryption so Google Drive only stores encrypted backup
data. Use rclone only as the transport layer.

Back up these data classes separately:

| Class | Source | Backup method |
|---|---|---|
| Nix configuration | Git repo and encrypted secrets | Git remote plus encrypted `sops` files |
| Host identity | age keys, SSH host keys, Tailscale state if needed | Small encrypted emergency backup |
| PostgreSQL | `pg_dump` or `pg_dumpall` into staging | Restic backup of dump directory |
| Valkey | RDB/AOF if used by durable services | Restic backup after a consistent save |
| App data | `/mnt/storage/app/*` | Restic backup, app-specific quiesce when needed |
| Podman volumes | `/mnt/storage/podman` or explicit volume paths | Prefer app-native export or stopped-service backup |
| Observability | Grafana provisioning in Git, Prometheus/Loki optional | Usually short retention; do not over-prioritize |
| Media/files | Immich, Paperless, Nextcloud, sync data | Restic backup, possibly different retention |

Initial retention policy:

```text
hourly: 24
daily: 14
weekly: 8
monthly: 12
```

Operational rules:

- Alert if the latest successful backup is older than 30 hours.
- Run `restic check` on a schedule.
- Run one small restore test every month.
- Keep at least one restore procedure documented near the backup module.
- Do not count synced files as backups unless deletion and corruption recovery are tested.
- Do not back up plaintext secrets; back up encrypted `sops` material and the keys needed to decrypt it.

Suggested restore tests:

1. Restore a PostgreSQL dump into a temporary database.
2. Restore one app data directory into `/mnt/storage/backup/restore-tests/`.
3. Verify that restic can list snapshots from a fresh environment using only documented secrets.

## Observability Design

Keep observability state on the Orange Pi. The Raspberry Pi should expose
metrics, but it should not store the main Prometheus or log database on SD.

Recommended stack:

| Component | Host | Purpose |
|---|---|---|
| Prometheus | Orange Pi | Metrics storage and alert rules |
| Grafana | Orange Pi | Dashboards and alert UI |
| node_exporter | All Linux hosts | CPU, memory, disk, network, systemd basics |
| blackbox_exporter | Orange Pi or Raspberry Pi | HTTP/TCP endpoint probes |
| Traefik metrics | Raspberry Pi | Ingress request rate, status codes, latency |
| Blocky metrics | Raspberry Pi and GCE | DNS queries, blocks, upstream failures |
| Loki or Grafana Alloy | Orange Pi plus agents | Journal and service logs if needed |
| SMART exporter or script | Orange Pi | NVMe health and temperature |
| Restic metrics script | Orange Pi | Backup age, duration, success, repo size |

Grafana Alloy is worth considering once logs become important because it can
collect logs and metrics through one agent-style service. Start simple with
Prometheus and node exporters, then add logs after the basic dashboards are
stable.

Minimum dashboards:

| Dashboard | Panels |
|---|---|
| Homenet overview | Host up/down, DNS health, edge health, service count, backup age |
| Edge gateway | Traefik requests, 4xx/5xx, latency, cert expiry, Tailscale state |
| DNS | Query rate, blocked rate, cache hit rate, upstream errors, GCE fallback health |
| Main server | CPU, memory, NVMe usage, IO pressure, systemd failed units |
| Storage and backup | Disk usage, backup freshness, restic duration, restore-test age |
| Databases | PostgreSQL up, connections, size, slow/error indicators |
| Containers | Podman service states, restart count, memory, CPU |
| Worker | Desktop awake/asleep, WOL events, GPU backend reachable, routed jobs |
| AI routing | OmniRoute or llama-swap health, model endpoint availability, probe latency |

Initial alerts:

| Alert | Condition |
|---|---|
| EdgeGatewayDown | Raspberry Pi unreachable for 2 minutes |
| MainServerDown | Orange Pi unreachable for 2 minutes |
| GceDnsDown | GCE Blocky metrics or DoH probe fails for 5 minutes |
| LanDnsFailing | LAN DNS probe fails for 2 minutes |
| TraefikHigh5xx | Edge 5xx rate spikes for 5 minutes |
| CertExpiresSoon | Any managed cert expires in less than 14 days |
| BackupStale | No successful backup in 30 hours |
| RestoreTestStale | No restore test in 45 days |
| DiskHigh | Persistent filesystem above 85% for 30 minutes |
| NvmeHealthBad | SMART health reports warning or critical state |
| PostgresDown | PostgreSQL unavailable for 2 minutes |
| WorkerNeededButOffline | A desktop-backed route is requested while the worker is asleep |

Use the existing Grafana provisioning pattern under
`hosts/homolab/services/edge/monitoring.nix` as the template, but move the final
monitoring module to the Orange Pi host when that host exists.

## Wake-on-LAN Design

Use the Raspberry Pi or Orange Pi as the WOL sender.

Expected flow:

1. A user or service requests a compute-heavy task.
2. The always-on host checks whether the desktop is reachable.
3. If unavailable, it sends a Wake-on-LAN magic packet.
4. The service waits, retries, or returns a clear pending state.
5. Once the desktop is reachable, traffic routes to the desktop worker.

Keep WOL helper behavior explicit. Avoid silently making every failed backend request wake the desktop unless the service is designed for that.

## Migration Order

### Phase 1: Board Bring-up

- Install and validate the target OS on both boards.
- Confirm network stability, SSH access, time sync, and reboot behavior.
- Confirm Orange Pi 5 Pro NVMe support and boot behavior.
- Confirm Raspberry Pi 5 power supply stability.
- Confirm desktop Wake-on-LAN from both ARM boards.
- Add temporary host records and Tailscale names for both boards.
- Install only SSH, Tailscale, time sync, and node exporter at first.
- Reboot each board several times and confirm it returns without manual steps.

Exit criteria:

- Both boards can be rebuilt or redeployed from the repo.
- Both boards are reachable over LAN and Tailscale.
- Orange Pi NVMe survives reboot and is mounted at the intended path.
- Raspberry Pi remains stable under DNS/proxy-like network load.

### Phase 2: Edge Split

- Move or duplicate DNS, VPN, and reverse proxy responsibilities to the Raspberry Pi.
- Keep existing desktop routes as upstreams during transition.
- Confirm public ingress, internal LAN access, and tailnet access.
- Make the Raspberry Pi configuration recoverable from repo-managed state.
- Keep GCE DNS alive as fallback during the transition.
- Add edge metrics before moving important routes.
- Route only one low-risk service through the Raspberry Pi first.

Exit criteria:

- LAN clients can use the Raspberry Pi DNS resolver.
- Public or tailnet routes can reach one test service through the Raspberry Pi.
- GCE DNS still answers independently.
- Existing desktop-hosted services still work through temporary upstream routes.

### Phase 3: Main Server Migration

- Move stateful services to the Orange Pi one by one.
- Start with low-risk internal services.
- Move databases only after backup and restore paths are tested.
- Keep service data on NVMe-backed paths.
- Avoid putting durable service data on the Raspberry Pi SD card.
- Move Prometheus and Grafana to the Orange Pi early so later migrations are visible.
- Add backup jobs before moving important app data.
- Move PostgreSQL only after a dump and restore test succeeds.
- Move Authelia after PostgreSQL is stable.
- Move each public route at the Traefik layer after its upstream has been validated.

Suggested order:

1. Grafana and Prometheus.
2. Backup module and restore-test timer.
3. PostgreSQL and Valkey.
4. Authelia.
5. Dashboard and internal services.
6. Forgejo or code services.
7. Larger file/media services.
8. AI routing that does not require the desktop GPU.

### Phase 4: Desktop As Worker

- Remove always-on service dependencies from the desktop.
- Keep only GPU and heavy compute services there.
- Add health checks and clear routing behavior for desktop-backed services.
- Verify desktop sleep, wake, service readiness, and shutdown behavior.
- Add WOL service or script on Raspberry Pi and Orange Pi.
- Add worker readiness probes.
- Make AI routing tolerate the desktop being asleep.
- Document which routes may wake the desktop.

### Phase 5: Backup And Failure Testing

- Back up Orange Pi service data to a separate disk or remote target.
- Test restore of at least one database-backed service.
- Test Raspberry Pi failure: Orange Pi should remain reachable over LAN.
- Test Orange Pi failure: Raspberry Pi should still provide DNS, VPN, and WOL where possible.
- Test desktop offline behavior for GPU-backed services.
- Test Google Drive credentials from a clean environment.
- Test restoring one service into a temporary path without touching production data.
- Test Raspberry Pi SD card loss by confirming config can recreate the edge host.

### Phase 6: Cleanup And Naming

- Rename service constants from `homolab`-specific names to `homenet` or role-based names.
- Remove stale desktop service state after Orange Pi services are stable.
- Archive old migration notes that no longer describe the active topology.
- Update `README.md` only with concise operator-facing commands and host roles.

## Repo Impact

Likely future changes:

- Add new host entries for the Raspberry Pi 5 and Orange Pi 5 Pro.
- Split existing `homolab` services into edge, main-server, and worker roles.
- Add shared constants for hostnames, LAN IPs, and service ports.
- Add WOL helper configuration or script.
- Revisit backup paths and retention once Orange Pi storage layout is defined.
- Add a backup module under the Orange Pi service tree.
- Add dashboard and alert provisioning that understands multiple hosts.
- Keep GCE DNS as its own host rather than folding it into the edge gateway.

Possible future shape:

```text
hosts/
  edge-rpi5/
    configuration/
    services/
      dns.nix
      tailscale.nix
      traefik.nix
      wol.nix
  opi5-main/
    configuration/
    services/
      backup.nix
      database.nix
      monitoring.nix
      podman.nix
      storage.nix
  desktop-worker/
    configuration/
    services/
      ai-worker.nix
      wol-target.nix
  gce-dns/

lib/
  homenet.nix
```

`lib/homenet.nix` should hold shared domains, host addresses, service ports,
and tailnet names. Avoid scattering literal IPs and ports across host modules.

No immediate Nix changes are made by this plan.

## Open Questions

- Whether the Raspberry Pi should boot from SD only or use USB SSD for better durability.
- Whether the Orange Pi 5 Pro will run NixOS directly or another OS with a lighter deployment path.
- Which services currently on `homolab` require GPU or large compute.
- Whether public ingress should terminate only on the Raspberry Pi or whether internal-only routes should bypass it.
- What backup target should protect the Orange Pi NVMe data.
- Whether Google Drive should be the only remote backup target or just the first one.
- Whether logs are valuable enough to add Loki/Grafana Alloy immediately.
- Whether the Raspberry Pi should be the only Tailscale subnet router or the Orange Pi should be a standby router.
- Whether service data should use one large NVMe filesystem or separate datasets/subvolumes.
- Whether media-heavy services should have a different backup retention from databases and documents.
