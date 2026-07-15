# TempestMiku on lumo — deployment brief

Date: 2026-07-15

## Outcome

Run the TempestMiku Rust API and worker continuously on lumo without replacing the existing
Hermes Agent deployment. Expose it at `https://miku.justaslime.dev` and deliver Android approval
notifications through the self-hosted `https://push.justaslime.dev` UnifiedPush distributor.

## Decisions

- Pin the public TempestMiku Git revision and build a glibc container on lumo.
- Run one `TM_SERVER_ROLE=all` process for the single-owner deployment.
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
- Do not enable Firebase, OMP ACP, live external research, external embedding providers, or
  self-evolution writes.
- Do not mark P6 complete without the physical killed-process request/resolution canary.

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
- The final physical Android canary proves approval request and resolution delivery while the app
  process is killed.

## Fresh-thread prompt

Use this plan as the project brief. First read the whole brief, then implement or operate it.
Preserve the stated constraints, non-goals, and acceptance checks. If anything is ambiguous, ask
only the smallest blocking question before building.
