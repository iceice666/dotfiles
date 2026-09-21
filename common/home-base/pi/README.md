# Pi extensions

`../pi.nix` installs `extensions/` for every host with `features.pi = true`
(m5pro, framework, homolab, and lumo). Home Manager recursively links the files
from the Nix store into `~/.pi/agent/extensions/`, preserving sibling imports
without taking ownership of unrelated local extensions.

| Extension | Purpose |
|---|---|
| `agent-team/` | Persistent Pi RPC workers, team messaging, explicit waits and observation UI |
| `ask-question/` | Structured human questions, including worker-to-parent routing |
| `background-task/` | Session-local background Bash jobs, explicit waits and bounded logs |
| `todo/` | Session-backed task tracking and progress UI |
| `dot-continue/` | Standalone `.` means `continue` in an idle interactive conversation |
| `btw/` | `/btw` side questions while the main agent runs, without changing its context |
| `status-line.ts` | Model/thinking, Git state, elapsed time, context and selectable live-agent footer rows |
| `exa-search/` | Bounded public web search through Exa, OpenAI, or Claude (`web_search`) |
| `analyze-image/` | Local image analysis through a configured vision model, returning text (`analyze_image`) |
| `observational-memory/` | Upstream Observational Memory 3.1.3 plus the repo-owned rate-limit fallback patch, pinned and installed by Nix for durable ledger-backed memory |
| `cache-safe-compaction/` | Best-effort post-compaction warm-up of the new OpenAI prompt-cache lineage |

The pinned `pi-bin` supplies the extension SDK imports at runtime; no npm install
is needed on deployed hosts. Bash is installed explicitly for background jobs;
Git and Node.js are supplied by the shared CLI baseline. Extensions execute with
the invoking user's permissions, including root on lumo. These extensions are
not a sandbox or automatic command-approval system.

## First adoption

Existing unmanaged files are deliberately **not** force-overwritten. Before the
first switch, quit Pi (including team workers and background jobs) and move only
these managed entries outside the auto-discovery directory. For example:

```sh
backup="$HOME/.pi/extensions-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup"
for entry in agent-team ask-question background-task todo dot-continue btw status-line.ts exa-search analyze-image observational-memory cache-safe-compaction; do
  source="$HOME/.pi/agent/extensions/$entry"
  if [ -e "$source" ] || [ -L "$source" ]; then
    mv "$source" "$backup/"
  fi
done
```

Then run the host's normal switch recipe and restart Pi. Keep the backup until
the new extensions have been verified. Subsequent updates use normal host
build/switch workflows; edit the repo sources, not the installed store links.
Do not use `pi install` to install a second copy of these extensions.

Authentication, trust decisions, sessions, team archives and temporary
background logs remain unmanaged. The Lumo audit explicitly disables extension
discovery and is unaffected.

`settings.json` is only partially managed. A `piSettings` activation step merges
the repo-owned keys (`theme`, `hideThinkingBlock`, and the
`observational-memory` defaults) into the existing file with `jq`; every other
key stays runtime-owned and writable, so `/model`, `/settings` and
`lastChangelogVersion` still persist. On hosts with `features.themegen` the
wallpaper-derived `~/.pi/agent/themes/themegen-{dark,light}.json` are installed
and the theme resolves to `themegen-light/themegen-dark`, matching Kitty's wallpaper-generated light/dark palettes;
other hosts keep the built-in `light/dark` pair. Changing the theme via
`/settings` is overwritten on the next switch — edit the repo instead. If
`settings.json` is not valid JSON, activation warns and leaves it untouched.

## Observational memory and cache-safe compaction

Nix pins upstream `pi-observational-memory` 3.1.3, applies
`patches/observational-memory-rate-limit-fallback.patch`, and installs the
resulting `src/` as the managed `observational-memory/` extension. Do not also
run `pi install npm:pi-observational-memory`; duplicate copies would register
competing memory workers and compaction hooks. The managed defaults use
`cliproxyapi/gpt-5.6-sol` at low thinking for background observer/reflector/dropper
work, cap their requested output at 8192 tokens, and scale proactive compaction
to 68% of the active model context window. Project-local Pi settings may still
override these defaults at runtime.

### Rate-limit model fallback (local patch)

Upstream accepts only one background model, so a 429 on that single account
stops consolidation for as long as the limit holds. The patch adds two settings
keys:

- `fallbackModels`: ordered alternates, each optionally with its own `thinking`.
  Managed default: `cliproxyapi-claude/claude-sonnet-5`, inheriting the
  preferred model's thinking level.
- `rateLimitCooldownMs`: how long a throttled model is skipped (default and
  managed value: 900000, i.e. 15 minutes).

Only rate-limit-shaped stream failures (HTTP 429, rate limit, quota,
`RESOURCE_EXHAUSTED`, `overloaded_error`) arm a cooldown; auth errors and
oversized prompts still fail loudly, because a second model would fail the same
way. The switch is announced once per fallback, `/om:status` lists cooling-down
models with the remaining time, and the preferred model is used again as soon as
its cooldown expires. If every candidate is cooling down the preferred one is
tried anyway, so a stale cooldown cannot disable memory.

The patch is generated against the exact upstream tag in `../pi.nix`. To bump
the pin, clone the new tag, apply the patch, resolve any conflicts, run the
upstream suite (`npm install && npx vitest run && npx tsc --noEmit`), and
regenerate the patch with `git diff` before changing `rev` and `hash`.

Observational Memory owns the content of an extension-provided compaction:
ledger entries are folded into a deterministic memory summary. The sibling
`cache-safe-compaction/` extension never registers `session_before_compact`; it
waits until Pi has saved the compaction and rebuilt the foreground context, then
sends one bounded, non-persisted warm request using the same session cache key.
It runs only for explicitly opted-in OpenAI-compatible providers, so the managed
Claude provider cannot receive an extra long-retention cache write. Warm-up is
best-effort: timeout, quota, or provider failure leaves the successful compaction
intact and the next turn proceeds normally. See
[cache-safe-compaction/README.md](extensions/cache-safe-compaction/README.md).

## Instructions, workflows and search

Pi receives the shared agent-neutral `../agent-instructions.md` as
`~/.pi/agent/AGENTS.md`. If an unmanaged file already exists there, back it up
before the first switch; Home Manager will not force-overwrite it.

Invoke `/skill:next-milestone` to use the shared skill and its `workflows/pi.md`
adapter. It maps the canonical review/verify/commit process to the team and todo
extensions; no OMP-specific tools or extra slash-command alias are required.

`web_search` defaults to Exa's fixed HTTPS search endpoint. Optional
`source: "openai"` or `source: "claude"` uses native search through fixed
CLIProxyAPI endpoints and the existing Pi provider credentials, returning
sources and separately labeled model synthesis. No automatic fallback occurs.
The
`~/.pi/agent/exa-api-key` helper reads the SOPS-backed `exa_api_key` on each
request; credentials are not stored in settings, source files, or environment
files. A custom `PI_CODING_AGENT_DIR` needs its own helper at `exa-api-key`.
See [exa-search/README.md](extensions/exa-search/README.md) for limits and tests.
Search queries leave the host: never include private source or credentials.
Results are untrusted evidence and may be incomplete; cite URLs, and fetch the
full source separately when needed. This is not a browser integration.

## Browser access (m5pro and Framework)

These two hosts additionally import `../browser.nix`: pinned `playwright-cli`,
a `playwright-read` rendered-page Markdown helper, and the agent-neutral
`playwright-browser` skill. Invoke `/skill:playwright-browser`; no MCP bridge or
additional Pi extension is needed. Each task/worker owns a separate ephemeral
browser session. Sandbox-enabled browser defaults live in
`~/.playwright/cli.config.json`; runtime profiles and artifacts remain unmanaged.
Homolab and Lumo do not receive this integration. See
[the package guide](../../../pkgs/playwright-cli/README.md) for usage, privacy,
first-adoption precautions and validation.

## Image analysis

`analyze_image` sends a local image and question to a configured vision model
(default `cliproxyapi-claude/claude-sonnet-5`) and returns text to the current
model, including text-only models. It uses registry-managed authentication and
sends no conversation history or tools. Images leave the host and consume model
quota; never send sensitive images without authorization. See
[analyze-image/README.md](extensions/analyze-image/README.md) for supported formats,
limits, tests and activation. Pasted chat attachments are not handled automatically.

## Continuing a stopped turn

When the current interactive Pi conversation is idle (after a completed reply or
an Escape interruption), submit `.` on its own to send `continue` instead.
Surrounding whitespace is ignored. This is an ordinary user prompt, not an
approval or a restart of stopped team workers. Busy/queued input, RPC and
extension-injected messages, image attachments, paths and other text are left
unchanged. To send a literal dot while idle, quote it or put it in a code span.

## Side questions while running

Use `/btw <question>` to ask the currently selected model a separate question
without interrupting the main agent. It receives a bounded text snapshot of the
conversation and no tools. Answers are saved as display-only transcript cards,
not main-agent context. `/btw cancel` stops only the side request. Additional
model quota is consumed; see [btw/README.md](extensions/btw/README.md) for context,
limits and a manual smoke check.

## Viewing team workers

Live workers appear directly in the status footer, one agent per row. Idle
workers remain visible; stopped or failed workers disappear without deleting
their session archives. There is no separate team widget, picker panel or
Ctrl+Shift+T shortcut.

With an empty input editor, press ↓ to select the first worker, then ↑/↓ to
navigate and Enter to open its read-only transcript. Esc (or ↑ on the first
row) returns to editing. Typing also returns to editing without dropping the
character. Nonempty editor text and dialogs keep their normal key handling.
`/team attach NAME` can still inspect an archived worker; `/team` and
`/team status` report team state. See [agent-team/README.md](extensions/agent-team/README.md).

## Waiting for work

Use `background_task({ action: "wait", id, timeout: 60 })` to wait for a
background job, or `agent_wait({ agent: "reviewer", timeout: 60 })` to wait for
a team worker. These are model tools, not slash commands. Both wait without
polling, default to 60 seconds, and accept a positive timeout up to 86400 seconds.
Timeout or Esc cancels only the wait, not the underlying job or worker.
Inspect the returned outcome: ending a wait does not by itself mean the work
succeeded. See the extension READMEs for exact completion and question semantics.

## Development

Tests and dependency metadata live here for development only and are not runtime
requirements. See each extension's README for behavior and test coverage. Keep
Pi SDK development dependencies aligned with `pkgs/pi-bin/default.nix`.

From the repository root (Node 22.19+ and Bun required):

```sh
cd common/home-base/pi
bun install --frozen-lockfile --ignore-scripts
bun run test
```

The test suite resolves the local pinned SDK, not a machine-specific global npm
installation. Dependency lifecycle scripts are not needed. The two legacy
real-Pi smoke tests are explicitly skipped until they use an isolated,
fail-closed provider fixture; `--offline` alone does not block completion API
requests. Enabled tests use no live models or credentials. Status-line tests cover
live-agent rows, keyboard selection, event integration and cleanup.
