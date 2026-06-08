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
Internet / LAN
    |
Raspberry Pi 5
edge gateway, VPN, DNS, reverse proxy, WOL
    |
Orange Pi 5 Pro
main server, containers, databases, persistent storage
    |
Desktop
sleeping GPU and compute worker
```

The Raspberry Pi owns the front door. The Orange Pi owns application state. The desktop is only awakened for jobs that need its GPU or larger compute budget.

## Fixed Decisions

- Treat the Raspberry Pi 5 SD card as disposable or mostly stateless.
- Put persistent service data on the Orange Pi 5 Pro NVMe.
- Keep normal user-facing services available while the desktop is asleep.
- Use Wake-on-LAN to start the desktop from either the Raspberry Pi or Orange Pi.
- Keep the Orange Pi reachable directly over LAN even if the Raspberry Pi gateway is down.
- Back up Orange Pi NVMe data to a separate target. NVMe is primary storage, not a backup.
- Validate Orange Pi 5 Pro NixOS support before migrating critical services.

## Service Placement

### Edge Gateway Services

Candidate services for the Raspberry Pi 5:

- Traefik edge routes.
- ACME certificate management.
- Tailscale entrypoint or subnet routing.
- LAN DNS.
- SSH bastion.
- Wake-on-LAN helper.
- Lightweight uptime checks.

The Raspberry Pi should forward most application traffic to the Orange Pi. It should not own application databases or large runtime state.

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

Services currently running on the desktop should move here unless they require the desktop GPU or high sustained compute.

### Desktop Worker Services

Candidate desktop-only workloads:

- Local LLM backends that require the desktop GPU.
- Build workers.
- Transcoding workers.
- Batch jobs.
- Large code or document processing tasks.

The Orange Pi can act as the stable API endpoint and route to the desktop only when it is awake.

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

### Phase 2: Edge Split

- Move or duplicate DNS, VPN, and reverse proxy responsibilities to the Raspberry Pi.
- Keep existing desktop routes as upstreams during transition.
- Confirm public ingress, internal LAN access, and tailnet access.
- Make the Raspberry Pi configuration recoverable from repo-managed state.

### Phase 3: Main Server Migration

- Move stateful services to the Orange Pi one by one.
- Start with low-risk internal services.
- Move databases only after backup and restore paths are tested.
- Keep service data on NVMe-backed paths.
- Avoid putting durable service data on the Raspberry Pi SD card.

### Phase 4: Desktop As Worker

- Remove always-on service dependencies from the desktop.
- Keep only GPU and heavy compute services there.
- Add health checks and clear routing behavior for desktop-backed services.
- Verify desktop sleep, wake, service readiness, and shutdown behavior.

### Phase 5: Backup And Failure Testing

- Back up Orange Pi service data to a separate disk or remote target.
- Test restore of at least one database-backed service.
- Test Raspberry Pi failure: Orange Pi should remain reachable over LAN.
- Test Orange Pi failure: Raspberry Pi should still provide DNS, VPN, and WOL where possible.
- Test desktop offline behavior for GPU-backed services.

## Repo Impact

Likely future changes:

- Add new host entries for the Raspberry Pi 5 and Orange Pi 5 Pro.
- Split existing `homolab` services into edge, main-server, and worker roles.
- Add shared constants for hostnames, LAN IPs, and service ports.
- Add WOL helper configuration or script.
- Revisit backup paths and retention once Orange Pi storage layout is defined.

No immediate Nix changes are made by this plan.

## Open Questions

- Whether the Raspberry Pi should boot from SD only or use USB SSD for better durability.
- Whether the Orange Pi 5 Pro will run NixOS directly or another OS with a lighter deployment path.
- Which services currently on `homolab` require GPU or large compute.
- Whether public ingress should terminate only on the Raspberry Pi or whether internal-only routes should bypass it.
- What backup target should protect the Orange Pi NVMe data.
