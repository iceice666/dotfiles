# Cache-safe compaction

Warms the new foreground prompt-cache lineage immediately after Pi successfully
writes a compaction entry. It is intentionally independent from the extension
that creates the summary: Observational Memory or Pi's native summarizer keeps
sole ownership of `session_before_compact`, while this extension observes only
`session_compact`.

The warm request rebuilds the active post-compaction messages, effective system
prompt and active tools, then sends a non-persisted, low-output request with the
foreground session ID. Reusing that ID preserves Pi's `prompt_cache_key` and the
CLIProxyAPI affinity headers. The response is discarded and never enters the
session.

## Scope and failure policy

Warm-up is enabled only when all of these are true:

- the model uses Pi's `openai-completions` adapter;
- its compatibility settings explicitly set `supportsLongCacheRetention = true`;
- the compaction entry has not already been attempted in this process.

The managed `cliproxyapi` provider meets these conditions. The Claude provider
does not, so this extension cannot accidentally create an additional Anthropic
long-retention cache write.

A warm request uses `toolChoice: "none"`, minimal reasoning effort, at most 16 output tokens,
no retries and a 30-second deadline. Provider failures, quota exhaustion and
timeouts do not roll back compaction or block the session permanently. Error
text is not displayed because provider errors can contain request payloads or
credentials. Session shutdown aborts an in-flight warm request.

## Current Pi API limitation

`modelRegistry.complete()` does not pass through the foreground Agent's
`context`, `before_provider_request`, `before_provider_headers`, or
`after_provider_response` extension hooks. This extension reconstructs ordinary
Pi context from public APIs, but another extension that mutates foreground
requests through those hooks can still make the warm request differ from the
next real request. A future Pi core `warmCurrentContext()` API would remove that
limitation.

## Tests

From `common/home-base/pi`:

```sh
bun test extensions/cache-safe-compaction/tests/extension.test.ts
```

Tests use no live model or credential.
