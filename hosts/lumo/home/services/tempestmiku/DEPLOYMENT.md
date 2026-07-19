# Reference deployment: TempestMiku on lumo and homolab

Updated: 2026-07-19

This runbook is intentionally specific to the project owner's Nix/SOPS/Tailscale environment. It is
not a prerequisite for TempestMiku and should not be presented as the portable installation path.
Users with other package managers, secret stores, private networks, TLS proxies, or supervisors
should follow TempestMiku's environment-neutral `docs/deploy-coordinator-worker.md` first, then use
this document only as a worked reference implementation.

## Outcome

Run the sole authoritative TempestMiku coordinator continuously on lumo without replacing the
existing Hermes Agent deployment. Expose it at `https://miku.justaslime.dev`, deliver Android
approval notifications through the self-hosted `https://push.justaslime.dev` UnifiedPush
distributor, and delegate only linked-host calls to the signed `tm-worker` on homolab.

## Decisions

- Pin the public TempestMiku Git revision and build a glibc container on lumo.
- Run one `TM_SERVER_ROLE=all` process for the single-owner deployment.
- Treat `TM_SERVER_ROLE=all` as lumo's internal durable turn/dream/cron supervision. It does not
  create a second public server: homolab runs only `tm-worker` and has no model, session, memory,
  client, or independent approval authority.
- Send `fs.*`, `code.search`, `proc.run`, and `linked://` jobs to homolab's Tailnet-only worker with
  the shared SOPS-managed HMAC key. Keep lumo approvals authoritative, persist worker job states,
  and fail visibly with no local fallback when homolab is unavailable.
- Reuse lumo PostgreSQL 17 over its Unix socket with peer authentication; do not expose Postgres
  over TCP or duplicate the database service. Install pgvector in the TempestMiku database.
- Run the pinned BGE-M3 embedding model in a separate loopback-only Ollama container with cloud
  access disabled. TempestMiku must fall back to typed lexical recall when it is unavailable.
- Reuse lumo CLIProxyAPI for model requests and its existing shared API key.
- Store the independent 32-byte push-registration encryption key in a lumo-scoped SOPS file.
- Persist artifacts, managed skills, and mode addenda under `/var/lib/tempestmiku`; persist local
  embedding weights under `/var/lib/tempestmiku-embeddings`.
- Keep the server loopback-only behind Traefik. TempestMiku device auth remains authoritative;
  do not insert Authelia into mobile API, SSE, pairing, or notification-action flows.
- Keep `lumo-hermes-agent` installed, running, and independently reversible.

## Non-goals

- Do not migrate Hermes data or cut traffic away from Hermes.
- Do not run a second `tm-server`, model, memory store, or approval authority on homolab.
- Do not automatically clone repositories, grant ambient host access, or fall back to lumo-local
  linked execution when homolab is unavailable.
- Do not claim hostile-kernel containment or multi-owner isolation. M4 covers hostile workloads on
  the trusted owner-controlled homolab kernel.

## Sources of truth

- `flake.nix` and `flake.lock` pin the TempestMiku flake used for the homolab worker package/module.
- `hosts/homolab/services/ai/tempestmiku-worker.nix` selects `nixosModules.m4Worker`, the Tailnet
  listener, and the shared signing credential.
- `hosts/lumo/home/services/tempestmiku/default.nix` independently pins the coordinator image
  source archive and renders `TM_REMOTE_WORKER_CONFIG`.
- `sensitive/shared/tempestmiku-worker.key` is the SOPS-encrypted shared HMAC key. It must decrypt to
  exactly 64 lowercase hexadecimal characters and must never be printed or committed as plaintext.
- `lib/homolab.nix` owns the Tailnet address and port numbers.

The worker flake pin and coordinator image pin are intentionally independent. A worker-module-only
change requires updating the flake input but does not require rebuilding the lumo image. Any Rust
change used by `tm-server` requires updating the lumo `sourceRev` and both raw-archive hashes.

## Prepare a release on m3air

Start with clean TempestMiku and dotfiles worktrees. Push the selected TempestMiku revision before
pinning it; GitHub archive URLs do not exist for an unpushed commit.

Update the worker package/module pin in `flake.nix`, then refresh only that input:

```sh
cd ~/dotfiles
nix flake update tempestmiku
```

When the coordinator binary source changed, also update `sourceRev` in
`hosts/lumo/home/services/tempestmiku/default.nix`. Obtain the hash of the raw GitHub tarball — do
not use `nix store prefetch-file --unpack`, because `pkgs.fetchurl` and the Dockerfile verify the raw
archive bytes:

```sh
export TEMPESTMIKU_REV='<40-character pushed commit>'
export TEMPESTMIKU_ARCHIVE="https://github.com/mozufu/TempestMiku/archive/${TEMPESTMIKU_REV}.tar.gz"
export TEMPESTMIKU_ARCHIVE_HASH="$(nix store prefetch-file --json "$TEMPESTMIKU_ARCHIVE" | jq -r '.hash')"
printf '%s\n' "$TEMPESTMIKU_ARCHIVE_HASH"
nix hash to-base16 "$TEMPESTMIKU_ARCHIVE_HASH"
```

Copy the returned SRI value into the `hash` field of the `sourceArchive` fetchurl, its base16
conversion into `sourceArchiveSha256`, and the revision into `sourceRev`. The three values must
describe the same raw archive.

Verify the encrypted worker credential without revealing it:

```sh
sops filestatus sensitive/shared/tempestmiku-worker.key | jq -e '.encrypted == true'
export TEMPESTMIKU_KEY_CHECK_DIR="$(mktemp -d)"
export TEMPESTMIKU_KEY_CHECK_PATH="$TEMPESTMIKU_KEY_CHECK_DIR/worker.key"
trap 'test ! -e "$TEMPESTMIKU_KEY_CHECK_PATH" || unlink "$TEMPESTMIKU_KEY_CHECK_PATH"; rmdir "$TEMPESTMIKU_KEY_CHECK_DIR"' EXIT
just secret-decrypt sensitive/shared/tempestmiku-worker.key "$TEMPESTMIKU_KEY_CHECK_PATH"
python3 -c 'import pathlib,re,sys; value=pathlib.Path(sys.argv[1]).read_bytes().strip(); raise SystemExit(0 if re.fullmatch(rb"[0-9a-f]{64}", value) else 1)' "$TEMPESTMIKU_KEY_CHECK_PATH"
unlink "$TEMPESTMIKU_KEY_CHECK_PATH"
rmdir "$TEMPESTMIKU_KEY_CHECK_DIR"
trap - EXIT
```

The `.sops.yaml` shared-secret rule must include both the lumo and homolab recipients before key
rotation. Use the repository secret helpers and a protected temporary plaintext file for rotation;
never edit the encrypted JSON as though it were the raw key and never leave the plaintext in the
worktree.

Run the preflight before committing:

```sh
nix fmt -- flake.nix hosts/lumo/home/services/tempestmiku/default.nix \
  hosts/homolab/services/ai/tempestmiku-worker.nix
git diff --check
nix flake check --no-build
nix eval .#nixosConfigurations.homolab.config.system.build.toplevel.drvPath --raw
nix eval .#homeConfigurations.lumo.activationPackage.drvPath --raw
```

Commit and push the scoped dotfiles change before touching either host. Homolab deploys from its own
clean `~/dotfiles` checkout, so an unpushed workstation change cannot be deployed reproducibly.

## Deploy homolab worker first

Wake homolab if necessary, connect through its Tailnet address, fast-forward its dotfiles checkout,
and switch the NixOS generation locally on that host:

```sh
ssh iceice666@100.110.95.111
cd ~/dotfiles
git status --short --branch
git pull --ff-only origin main
just homolab-switch
```

The module creates `/var/lib/tempestmiku-worker/linked/tempestmiku`, but deliberately does not put a
repository there. On first deployment, confirm the directory is empty before cloning. On later
deployments, require a clean checkout and move it to the exact TempestMiku flake revision selected
for the worker:

```sh
export TEMPESTMIKU_WORKER_REV='<revision pinned by the dotfiles TempestMiku flake input>'
export TEMPESTMIKU_WORKTREE='/var/lib/tempestmiku-worker/linked/tempestmiku'

sudo systemctl stop tempestmiku-m4-worker
sudo test -d "$TEMPESTMIKU_WORKTREE"
if sudo test -d "$TEMPESTMIKU_WORKTREE/.git"; then
  test -z "$(sudo -u tempestmiku-worker git -C "$TEMPESTMIKU_WORKTREE" status --porcelain)"
else
  test -z "$(sudo find "$TEMPESTMIKU_WORKTREE" -mindepth 1 -maxdepth 1 -print -quit)"
  sudo -u tempestmiku-worker git clone --no-checkout \
    https://github.com/mozufu/TempestMiku.git "$TEMPESTMIKU_WORKTREE"
fi
sudo -u tempestmiku-worker git -C "$TEMPESTMIKU_WORKTREE" fetch origin "$TEMPESTMIKU_WORKER_REV"
sudo -u tempestmiku-worker git -C "$TEMPESTMIKU_WORKTREE" checkout --detach "$TEMPESTMIKU_WORKER_REV"
sudo systemctl start tempestmiku-m4-worker
```

Never overwrite a non-empty unknown directory or silently discard local changes. Keep the checkout
detached at the reviewed revision so a later `origin/main` update cannot change the worker's view
without an explicit deployment.

Verify the service, immutable checkout, Tailnet health, and delegated cgroup:

```sh
systemctl is-enabled tempestmiku-m4-worker
systemctl is-active tempestmiku-m4-worker
sudo -u tempestmiku-worker git -C "$TEMPESTMIKU_WORKTREE" rev-parse HEAD
curl --fail --silent http://100.110.95.111:18787/v1/health | jq

systemctl show tempestmiku-m4-worker \
  -p User -p Group -p Delegate -p ControlGroup -p ActiveState -p SubState
wc -l </sys/fs/cgroup/system.slice/tempestmiku-m4-worker.service/cgroup.procs
cat /sys/fs/cgroup/system.slice/tempestmiku-m4-worker.service/cgroup.subtree_control
```

The delegated root process count must be zero, the `service` subgroup must contain the long-lived
worker, and `cgroup.subtree_control` must contain `cpu memory pids`.

Back on m3air, the bounded worker smoke should also pass:

```sh
cd ~/dotfiles
just homolab-tempestmiku-worker-smoke
```

## Deploy lumo coordinator

Run deploy-rs from the clean m3air dotfiles checkout after homolab is healthy:

```sh
cd ~/dotfiles
just lumo-build
just lumo-switch
just lumo-smoke
```

The first image build for a new Rust revision occurs on lumo and can take several minutes without
output during final release linking. A checksum mismatch must stop the deployment; correct the raw
archive hash rather than bypassing verification.

Verify the authoritative coordinator and its remote-only linked-host configuration without printing
credentials:

```sh
ssh root@lumo 'rc-service lumo-tempestmiku status'
ssh root@lumo 'curl --fail --silent http://127.0.0.1:18080/health'
ssh root@lumo 'podman inspect lumo-tempestmiku --format "{{range .Config.Env}}{{println .}}{{end}}" \
  | grep -E "^(TM_SERVER_ROLE|TM_REMOTE_WORKER_CONFIG|TM_HOST_CONFIG)="'
curl --fail --silent https://miku.justaslime.dev/health
```

Expected container environment: `TM_SERVER_ROLE=all`, one `TM_REMOTE_WORKER_CONFIG`, and no
`TM_HOST_CONFIG`. Here `all` means lumo's internal API plus durable turn/dream/cron supervision; it
does not mean another external server.

## Update m3air last

After both production services pass:

```sh
cd ~/dotfiles
just build
just switch
git status --short --branch
```

The final status must be clean and synchronized with `origin/main`.

## Release acceptance

Unsigned `GET /v1/health` proves only worker identity and readiness. A production release also needs
a signed read and an approval-gated `proc.run` through the lumo-side connector. Confirm that:

1. `fs.read` returns content from the provisioned checkout.
2. Re-submitting the exact durable job ID returns the retained terminal result without re-execution.
3. `proc.run` enters `awaiting_approval`, lumo resolves the exact action digest, and the command
   exits successfully inside bubblewrap/seccomp/cgroup isolation.
4. No per-run cgroup remains after completion.

For an attended no-fallback canary, stop homolab's worker briefly, confirm its Tailnet endpoint is
unreachable while lumo `/health` remains good, confirm the lumo container still has no
`TM_HOST_CONFIG`, and immediately restore the worker. Arrange restoration before stopping the
service; do not leave this test unattended.

The retained reference result and exact claim boundary live in TempestMiku
`docs/evidence/2026-07-19-m4-coordinator-worker.md`.

## Hardening compatibility

Do not re-add `ProtectKernelTunables`, `ProtectKernelLogs`, or `ProtectHostname` to the worker unit
without repeating the real nested bubblewrap canary. On the deployed systemd/kernel combination,
those outer namespace or `/proc` mounts prevent bubblewrap from mounting its private `/proc`.
`NoNewPrivileges`, empty capability sets, private devices/tmp, protected home/system/modules/clock,
strict read-only system paths, descriptor-pinned mounts, seccomp, and delegated per-run cgroups
remain enabled.

## Rollback

- If homolab fails before lumo changes, restore the prior dotfiles revision on homolab and switch
  that NixOS generation; leave the existing lumo coordinator untouched.
- If lumo activation fails, deploy-rs magic rollback retains the previous Home Manager generation.
  Fix the source pin/hash or configuration, then redeploy; do not manually mutate the running
  container to make it pass.
- If a completed release must be reverted, revert the scoped dotfiles commit, push it, deploy
  homolab first, restore the matching operator-provisioned checkout, then deploy lumo and m3air.
- Never rotate the shared HMAC key on only one host. A rotation is complete only after both worker
  and coordinator consume the same new encrypted value and the signed job canary passes.

## Acceptance checks

- The pinned image builds on aarch64 lumo and `lumo-tempestmiku` remains started under OpenRC.
- `lumo-tempestmiku-embeddings` remains started, binds only `127.0.0.1:11434`, and serves the pinned
  BGE-M3 model with Ollama cloud disabled.
- The `tempestmiku` role and database exist, ordered migrations pass, and restart preserves state.
- The `vector` extension exists and the active embedding generation remains usable across restart;
  provider loss remains an explicit lexical fallback rather than a turn failure.
- Loopback `/health` and public HTTPS `/health` pass; `/pair` advertises the public miku origin.
- Startup logs report the real LLM runner and `unifiedpush` configuration without exposing secrets.
- Existing lumo smoke checks and Hermes service health remain green.
- Homolab has exactly one `tempestmiku-m4-worker` service, no `tm-server`, a provisioned linked
  checkout, a durable job ledger, and a Tailnet health endpoint whose worker id is `homolab-m4`.
- A signed live read and approval-gated `proc.run` complete through homolab, and stopping the worker
  makes the coordinator call fail without local execution.
- The final physical Android canary proves approval request and resolution delivery while the app
  process is killed.

## Current production evidence

The 2026-07-19 rollout passed the full Rust workspace, strict Clippy/format, Nix evaluations, lumo
and homolab switches, m3air switch, signed read, durable job idempotency, lumo-resolved approval,
isolated `proc.run`, and attended fail-no-fallback canaries. Treat that evidence as a baseline, not
as permission to skip the checks for a later source, kernel, systemd, secret, or topology change.
