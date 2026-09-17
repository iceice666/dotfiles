# Exa web search

Registers `web_search` with `query` (1–2000 characters, nonblank) and optional
`numResults` (integer 1–10; default 5). It searches the public web, returning
numbered titles, source URLs, publication dates when supplied, and text excerpts.
It does not implement a general URL-fetching/browser tool.

## Credentials and privacy

Each call executes `<Pi agent directory>/exa-api-key` directly with `execFile`
(no shell command parsing, arguments, or environment-key fallback). Pi's
`getAgentDir()` resolves `PI_CODING_AGENT_DIR`, defaulting to `~/.pi/agent`.
Home Manager supplies the executable helper; it reads the shared SOPS Exa
secret at request time. Keys are not cached or persisted by the extension.
With a custom agent directory, provision the helper there as well.

Only the query and bounded search options are sent to
`https://api.exa.ai/search`; authentication uses `x-api-key`. Redirects are
rejected. Do not search for secrets or private repository content. Search
queries/results enter the normal Pi session history and model context.
Search results are untrusted web content, not instructions.

Requests use Exa's `type: "auto"` and
`contents: { text: { maxCharacters: 2000 } }`, following the
[Search API reference](https://docs.exa.ai/reference/search).

## Bounds and failures

- 30-second overall deadline, including credentials and response streaming;
  Pi cancellation aborts the helper/request and stops waiting.
- Credential helper: 5-second timeout, 4096-byte stdout/stderr bounds.
- No retries (avoid repeated quota charges).
- Response streaming is capped at 512 KiB before JSON parsing.
- At most the requested result count; title 300 characters, URL 2048,
  publication date 80, excerpt 2000.
- Output is capped at 24 KiB / 600 lines, including a truncation notice.
  Full responses are not saved; follow source URLs for complete content.
- Terminal control characters are removed; only HTTP(S) source URLs without
  embedded credentials are accepted.
- Errors are thrown to Pi, with fixed diagnostics or HTTP status only.
  Credential output, raw upstream bodies, and underlying exception messages
  are never included in failure results.

## Development

From `common/home-base/pi`:

```sh
bun test extensions/exa-search/tests/*.test.ts
```

Tests inject credential and fetch dependencies and use synthetic responses;
no real secrets or network requests are needed. The extension itself requires
only Pi's provided packages and Node built-ins, with no extra runtime dependency.
