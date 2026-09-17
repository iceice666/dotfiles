# Multi-source web search

Registers `web_search` with `query` (1–2000 characters, nonblank) and optional
`numResults` (integer 1–10; default 5) and `source` (`exa`, `openai`, or
`claude`; default `exa`). It searches the public web, returning
numbered titles, source URLs, publication dates when supplied, and text excerpts.
It does not implement a general URL-fetching/browser tool.

## Sources

```text
web_search({ query: "NixOS release announcement" })
web_search({ query: "NixOS release announcement", source: "openai" })
web_search({ query: "NixOS release announcement", source: "claude" })
```

Exa retains its existing behavior. OpenAI uses `gpt-6-astra` through
CLIProxyAPI's `/v1/responses`; Claude uses `claude-sonnet-5` through
`/v1/messages`. Both use native server-side search. Successful search execution
is required: a model answer without search evidence is an error. Source URLs
are deduplicated, and model synthesis is labeled separately from source text.
`numResults` limits listed sources, not upstream search calls or citations in
the synthesis. Incomplete model responses are explicitly marked; no automatic
continuation, backend fallback, or tool-level retry occurs. CLIProxyAPI may
still apply its own configured retries/account routing.

## Credentials and privacy

Each call executes `<Pi agent directory>/exa-api-key` directly with `execFile`
(no shell command parsing, arguments, or environment-key fallback). Pi's
`getAgentDir()` resolves `PI_CODING_AGENT_DIR`, defaulting to `~/.pi/agent`.
Home Manager supplies the executable helper; it reads the shared SOPS Exa
secret at request time. Keys are not cached or persisted by the extension.
With a custom agent directory, provision the helper there as well.

For `openai` / `claude`, Pi's model registry resolves the existing
`cliproxyapi` / `cliproxyapi-claude` provider credentials at request time.
The extension does not parse `models.json`, execute arbitrary key commands
itself, or require separate official API keys. Both proxy endpoints are fixed
to `https://cliproxyapi.justaslime.dev`; provider base URL overrides do not
redirect search traffic. Authentication uses a Bearer header. Only the query
and search instructions/options are sent, never the current session context.
Native searches consume the proxy's upstream account quota. These nested HTTP
requests are not currently added to Pi's token/cost totals.

For Exa, only the query and bounded search options are sent to
`https://api.exa.ai/search`; authentication uses `x-api-key`. Redirects are
rejected. Do not search for secrets or private repository content. Search
queries/results enter the normal Pi session history and model context.
Search results are untrusted web content, not instructions.

Requests use Exa's `type: "auto"` and
`contents: { text: { maxCharacters: 2000 } }`, following the
[Search API reference](https://docs.exa.ai/reference/search).

## Bounds and failures

- Overall deadline: 30 seconds for Exa, 120 seconds for native search,
  including credentials and response streaming. Pi cancellation aborts the
  helper/request and stops waiting. Registry credential resolution has no
  AbortSignal API: cancellation stops waiting but cannot stop its internal work.
- Credential helper: 5-second timeout, 4096-byte stdout/stderr bounds.
- No extension-level retries (avoid repeated quota charges).
- Native output budget: 4096 tokens; Claude search `max_uses`: 2.
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
