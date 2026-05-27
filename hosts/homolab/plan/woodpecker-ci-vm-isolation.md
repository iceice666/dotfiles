# Woodpecker CI Agent VM Isolation Plan

## Goal

Move Woodpecker job execution off the host and into an on-demand VM on the same physical machine.

This keeps the current host as the Woodpecker control plane while shifting the CI execution plane into a dedicated boundary that is easier to rebuild and safer to expose to untrusted pipeline code.

## Target Architecture

- Host machine keeps:
  - `woodpecker-server`
  - Forgejo
  - Traefik
  - existing homelab services
- CI VM runs only:
  - `woodpecker-agent`
  - rootless Podman
  - Buildah
  - minimal build tooling
- Woodpecker server stays on the host.
- Woodpecker agent moves into the VM.
- Pipelines execute in the VM, not on the host.

## Why This Direction

- Removes general CI execution from the host.
- Preserves the Buildah rootless migration path.
- Avoids reintroducing host-level trust through the host Podman socket.
- Simpler to operate than introducing Kubernetes only for CI isolation.
- Creates a disposable boundary for large builds and pipeline experiments.

## VM Sizing

Initial VM size:

- vCPU: `4`
- RAM: `8 GB`
- Disk: `80 GB` local storage

Allowed tuning range:

- vCPU: `2-4+`
- RAM: `6-16 GB`
- Disk: `50-100 GB`

Sizing notes:

- Start at `4 vCPU / 8 GB / 80 GB` because your pipelines target large projects.
- Increase RAM first if container builds or link steps become memory bound.
- Increase disk first if image layers, caches, or large worktrees begin to churn.

## Virtualization Stack

Recommended host stack:

- `libvirt`
- `qemu-kvm`

Reasoning:

- Mature and well understood.
- Good fit for same-host, on-demand VMs.
- Easier to isolate and lifecycle-manage than repurposing containers as quasi-VMs.

Current repo state:

- No VM stack is defined in the current NixOS config.
- `virsh` is not currently installed on the host.
- This plan therefore includes adding the host virtualization layer first.

## Runner Model Inside The VM

- Create a dedicated `ci` user.
- Run rootless Podman and Buildah under that user.
- Run `woodpecker-agent` in the VM.
- Switch the VM agent to Woodpecker `docker` backend.
- Point `WOODPECKER_BACKEND_DOCKER_HOST` at the VM's own rootless Podman socket.

This restores per-step container execution while keeping the container runtime trust boundary inside the VM instead of on the host.

## Network Design

Preferred network shape:

- VM has a private address on the same host bridge or LAN.
- No public ingress to the VM.
- Optional admin SSH only from LAN.

Allow outbound access only for:

- Woodpecker gRPC back to the host server
- Forgejo clone and fetch
- registry pull and push
- explicitly approved deployment targets

Avoid giving the VM access to:

- host Podman socket
- host Docker socket
- unrelated internal admin services
- broad access to local-only control endpoints unless required

## Secrets and Trust Material

Place only CI-specific secrets in the VM:

- Woodpecker agent secret
- registry credentials if required
- deployment credentials only for repos that actually deploy
- custom CA or registry CA required for internal registries

Do not copy unrelated host secrets into the VM.

Prefer:

- repo-scoped Woodpecker secrets
- short-lived credentials where possible
- minimal global secret surface

## Rootless Buildah/Podman Requirements

Inside the VM, validate:

- `/etc/subuid` and `/etc/subgid`
- `newuidmap` and `newgidmap`
- writable local storage for rootless container layers
- rootless overlay support or `fuse-overlayfs`
- registry trust configuration for internal registries

Tooling baseline in VM:

- `podman`
- `buildah`
- `git`
- `git-lfs`
- shell/coreutils
- CA certificates

## Woodpecker Policy Model After Migration

- Default normal repos to the VM-backed agent.
- Use agent labels so only selected workflows land on that runner.
- Keep host-local execution disabled for general use.
- If host-local execution remains at all, reserve it for a very small set of intentionally trusted infra jobs.

## Rollout Plan

### Phase 1: Host Virtualization

1. Add `libvirt` and `qemu-kvm` to the host config.
2. Define storage location for VM disks.
3. Define a private or bridged network for the CI VM.
4. Validate the host can create and start a local VM cleanly.

### Phase 2: CI VM Guest

1. Create a dedicated NixOS VM guest config.
2. Add the `ci` user and rootless container prerequisites.
3. Install Podman, Buildah, Git, Git LFS, and required CA files.
4. Enable rootless Podman socket for the CI user.
5. Add the Woodpecker agent service to the guest.

### Phase 3: Agent Cutover

1. Configure the VM agent to use the `docker` backend.
2. Point it to the VM-local rootless Podman socket.
3. Add Woodpecker agent labels for controlled scheduling.
4. Register and connect the VM agent to the host Woodpecker server.

### Phase 4: Validation

1. Run one non-critical pipeline.
2. Confirm clone, fetch, and artifact flow work.
3. Confirm rootless Buildah can build successfully.
4. Confirm registry auth and custom CA trust work.
5. Confirm no host socket or host filesystem dependency remains.

### Phase 5: Migration

1. Move normal CI repos to the VM-backed runner.
2. Observe disk, RAM, and cache pressure.
3. Tune VM size if needed.
4. Retire the host-local runner for general jobs.

## On-Demand Lifecycle

Design goal:

- VM exists on the same host but is started only when needed.

Operational model:

- VM remains powered off by default.
- Start the VM before heavy CI activity or when a maintenance window is expected.
- Stop it when not needed to reduce attack surface and idle resource use.

Possible future ergonomics:

- simple wrapper command to start the VM and wait for the agent to register
- systemd helper unit for lifecycle management
- optional scheduled shutdown after idle window

## Validation Checklist

- Woodpecker agent connects from the VM successfully.
- Pipelines no longer run on the host `local` backend for normal repos.
- Buildah works rootlessly inside the VM.
- Registry pulls and pushes succeed.
- Internal CA trust works if required.
- VM does not depend on any host container socket.
- A compromised CI job would be contained to the VM boundary rather than the main host.

## Risks and Caveats

- Woodpecker's `docker` backend with Podman is not officially supported upstream, so some compatibility gaps are possible.
- Large builds may pressure disk and RAM faster than expected.
- Rootless Buildah may still need tuning around storage driver behavior.
- If the VM is long-lived, image and workspace cleanup should be automated.

## Follow-Up Implementation Tasks

1. Add host virtualization services to this repo.
2. Add a NixOS guest definition for the CI VM.
3. Define VM lifecycle commands for create, start, stop, and rebuild.
4. Move Woodpecker agent config from host-local execution to VM execution.
5. Add agent labels and update repo scheduling policy.
6. Test one large project pipeline end-to-end.

## Recommendation Summary

Use an on-demand NixOS VM on the same physical host with `4 vCPU`, `8 GB RAM`, and `80 GB` local disk as the default starting point.

Run the Woodpecker agent plus rootless Podman/Buildah inside that VM, keep the Woodpecker server on the host, and use the VM as the dedicated CI execution boundary.
