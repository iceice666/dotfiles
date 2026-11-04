# lumo

Alpine 3.24 Raspberry Pi 5 (`homeConfigurations.lumo`), the data + apps + DNS +
edge plane. Shared Alpine/APK/Home Manager ownership, bootstrap hardening and
provisioning are in `common/home-alpine/README.md`.

```sh
just lumo-bootstrap          # converge the existing Alpine installation
just lumo-build              # dry-activate root Home Manager
just lumo-switch             # deploy root Home Manager
just lumo-smoke              # verify OpenRC services and local endpoints
just lumo-upgrade [apply]    # APK layer (kernel, OpenSSH, Tailscale); dry run by default
just cliproxyapi-reset-cooldown [provider] # clear CLIProxyAPI cooldowns (default codex)
```

Services (`home/services/`): Postgres, Valkey, git-server, Podman, Blocky,
Prometheus, Dynacat, CLIProxyAPI, Umami, LearnHarness, pirc gateway, the daily
audit, and the edge stack (`edge/`: Traefik, Authelia, Cloudflare DDNS) moved
from the retired gateway Pi.

## Network exposure

- Application backends (Dynacat, Umami, CLIProxyAPI, LearnHarness, Prometheus,
  Authelia) bind to loopback and are reached only through lumo's local Traefik.
- The firewall (`edge/nftables.nix`, mirrored in `scripts/alpine-bootstrap`)
  accepts only SSH, Blocky DNS, and HTTP/HTTPS on `tailscale0`, and only DNS and
  HTTP/HTTPS from `podman*`.
- Prometheus scrapes only lumo's local exporters; Traefik's ping/metrics entry
  points bind to loopback.
- Every websecure router carries the `security-headers` middleware (HSTS with
  subdomains, nosniff, SAMEORIGIN, strict referrer). Default TLS options require
  TLS 1.2+, strict SNI, and ECDHE AEAD suites.
- Traefik entry points use `aliasHeadersStrategy = delete`, dropping any request
  header whose name is not letters, digits, and dashes.
- Authelia `regulation` bans an account for 10 minutes after 3 failed attempts
  within 2 minutes.
- The whole CLIProxyAPI host, including `/v1`, is restricted to
  loopback/LAN/tailnet client IPs. Pi clients reach it over the tailnet because
  Blocky maps the name to lumo's tailnet address; public requests through
  Cloudflare get a 404.

## DNS (Blocky)

Blocky listens on lumo's Tailscale address (`100.120.152.7`) on TCP/UDP 53. Its
HTTP/Prometheus listener is loopback-only on port 4000; Traefik publishes DoH at
`https://dns.justaslime.dev/dns-query`. The tailnet global nameserver must point
to `100.120.152.7`.

lumo's own resolver order is not reliable for private names (Tailscale falls
back to the base `1.1.1.1` entry because the tailnet resolver is lumo itself),
so `blocky.nix` also maintains a marker-delimited `/etc/hosts` block mapping
every private name to the tailnet address; glibc-linked Nix binaries such as the
audit Pi depend on it.

## Service privileges

No Nix-managed service runs as root except the rootful Podman service itself.

- Authelia runs as `authelia`; its root `start_pre` stages 0400 copies of the
  sops secrets into `/run/lumo-authelia` because the standalone HM sops module
  cannot set per-secret owners.
- Traefik's wrapper reads the Cloudflare token as root, then `setpriv`s to
  `traefik` with only an ambient `CAP_NET_BIND_SERVICE` for :80/:443 (Alpine's
  OpenRC lacks libcap, so `supervise-daemon` cannot grant capabilities;
  `ip_unprivileged_port_start` stays at 1024).
- Both `start_pre` hooks `chown -R` their state directories so earlier
  root-owned `db.sqlite3`/`acme.json` migrate on first start.

## Containers

Rootful container images in `umami.nix` and `cliproxyapi-usage-keeper.nix` are
digest-pinned; bump digests deliberately. They are separate runtime boundaries
from host Node (see `docs/tls-trust.md`).

**Umami** pins the upstream 3.4.1 image by digest with explicit CA mounts. Its
data lives in lumo's host PostgreSQL 17 (`umami` role and database, password from
`sensitive/hosts/lumo/umami.yaml`), reached over loopback TCP with SCRAM;
`database.nix` listens on `127.0.0.1` only for this. The former dedicated
`postgres:16-alpine` container is gone: activation migrated its data once from
`/var/lib/umami/postgres` (kept for rollback; `/var/lib/umami/host-postgres`
marks completion). Umami runs Prisma migrations on startup, so activation writes
a `pg_dump` to `/var/lib/umami/backups/` before the first start of a changed
image (five newest kept) and records the running image in `/var/lib/umami/image`.

**Usage keeper** runs v2 (requires CLIProxyAPI 8.0.12+). It starts the binary
directly as the image's `app` uid (100:101) with every capability dropped
instead of the root entrypoint; `/var/lib/cliproxyapi-usage-keeper/data` is
owned by that uid. Before the first start of a changed image, activation stops
it, copies `app.db` (plus WAL/SHM) to a `pre-upgrade-*` directory under
`/var/lib/cliproxyapi-usage-keeper`, and records the image in `image`. Never
open a migrated v2 database with v1; roll back only from such a copy.

**LearnHarness** (`learnharness.nix`, `https://learn.justaslime.dev`) runs the
upstream Next.js app in browser mode. Upstream publishes no image, so lumo builds
`localhost/learnharness:<version>-<build id>` from the hash-pinned source tag,
`learnharness.Containerfile` and a digest-pinned `node:26-bookworm-slim`. A cold
build outlasts deploy-rs's confirm window, so activation builds a missing image
detached (log: `/var/log/lumo/learnharness-build.log`) and restarts the service
afterwards; superseded builds are pruned by label. The app has no user
authentication and all browsers share its keys and data, so the host is both
private-client-only and Authelia `two_factor`. The container runs as `node` with
dropped capabilities; `/var/lib/learnharness` holds data, the auth file and
`$HOME`. The shared CPA client key is injected as `CUSTOM_OPENAI_API_KEY`;
configure Settings → Providers → Custom endpoint with `http://127.0.0.1:20129/v1`
and API-key mode. To upgrade, bump `version`, `hash` and, deliberately, the
base-image digest.

## CLIProxyAPI

lumo runs CLIProxyAPI 8.x; the generated `config.yaml` still uses the legacy
layout, which v8 reads unchanged. The shared client key lives in
`sensitive/shared/cliproxyapi.yaml`.

The `account-quota` scheduler polls each Codex/Claude OAuth usage endpoint,
caches observations for `poll_interval_seconds` (900), and fails closed when it
cannot verify the reserve per upstream `AuthID`. A reserve withholds the account
once *either* the five-hour or the weekly window reaches its ceiling; the
per-account percentages in `sensitive/hosts/lumo/account-quota.yaml` cover both
windows unless a `weekly_reserve_percent_by_auth_id` entry overrides the weekly
one.

## Forgejo and Woodpecker (offline)

Temporarily offline. The module, encrypted secrets, and persistent data are
retained. `lumo.forgejoWoodpecker.enable` defaults to `false`; activation stops
the stack and removes its default-runlevel entries, and Traefik omits its routes.
Re-enable only after resolving the image's auxiliary OpenSSH listener conflict
with host port 22. `just lumo-smoke` expects the stack to remain offline.

## Daily audit

The collector discovers OpenRC commands through the system PATH, collects
file-based sysklogd logs and bounded rotated-log tails, and records individual
service status exit codes. Missing or truncated logs do not establish complete
24-hour authentication coverage. It also records patch-level evidence:
`apk list --upgradable` after a repository refresh, the installed-vs-running
`linux-rpi` kernel, core APK versions, the Nix-provided service versions of the
active generation, and Trivy HIGH/CRITICAL scans of the Alpine package database
(`/nix`, `/var`, and container storage skipped) and of the images backing
running containers (fixed-only). Trivy caches its database root-only under
`/var/cache/trivy` and needs outbound access to ghcr.io; scan failures are
recorded as collector gaps, not clean results. Nix closures are not CVE-scanned.

The reporter uses an audit-only Pi runner with the shared
`common/home-base/agent-model.nix` profile. Root collects evidence and sends mail
through Resend; `runuser` runs Pi as the non-login `homolab-audit` account, and
the runner refuses UID 0 or any other account. Root-owned evidence is
group-readable but not writable by that account. Each report uses a private 0700
temporary agent directory under `/run/homolab-audit`, a sanitized environment,
and a 0400 copy of only the model API key; the directory is removed on exit. The
account cannot read the root SOPS identity, original secrets, or Resend key.

The fixed runner invokes the pinned `pi-bin` directly with `--tools read,ls`,
`--no-approve`, and extension/skill/context/theme discovery disabled; it does
not load the interactive managed extension tree. This is Unix privilege
separation, not an OS sandbox: world-readable host files remain readable. Model
stderr is saved as root-only `pi-output.log`; reports and mail artifacts are
also root-only. Switching removes root's managed Pi launcher and symlinked
config, but leaves unmanaged `/root/.pi` settings/auth/sessions untouched; old
generations retain their previous closures until collected.
