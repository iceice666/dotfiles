# BTW side questions

While the main agent is working, enter:

```text
/btw 為什麼這裡選用 Home Manager？
/btw cancel
```

`/btw <question>` starts an independent, tool-free request using the currently
selected model and registry-managed credentials. It returns control to the editor
immediately, without waiting for, interrupting, steering, or resuming the main
agent. It also works when the main agent is idle. One question can run at a time;
`/btw cancel` cancels only the side request. Normal Esc behavior is unchanged.

The answer appears as a Markdown BTW card in the transcript. Question and answer
are saved as a plain custom session entry, so they survive reload but **never
enter the main agent's model context**. Subsequent BTW questions are independent:
they do not include previous BTW answers. Copy relevant text into a normal message
if you want the main agent to act on it. RPC clients receive the answer as a UI
notification; print/JSON modes are unsupported and make no request.

## Context and limits

- Sends a text snapshot of the active branch, respecting compaction, to the same
  provider as the selected model. This consumes additional model quota; normal
  session token/cost totals do not include these standalone calls.
- Snapshot includes text, tool call arguments/results and context-included Bash
  output. It excludes thinking, images, tool result details and UI-only custom
  entries. It keeps the latest 48,000 characters, with a truncation notice.
- This is a snapshot of persisted conversation, not live filesystem or process
  inspection. An in-flight assistant response or unfinished tool may be absent.
  No extra files, system prompt, skills or tools are sent.
- Questions are limited to 8,000 characters; replies to 4,096 output tokens and
  24,000 displayed characters. Reasoning uses provider defaults, independently
  of the main agent's thinking setting.
- A 120-second deadline bounds local waiting. No automatic retry or fallback.
  Cancellation aborts the provider request where supported; it cannot guarantee
  that upstream billing stops immediately.
- Session shutdown/reload/replacement and tree navigation cancel pending work;
  stale results cannot appear in a new session. Provider errors are redacted.

## Install and verify

Installed automatically by the recursive Home Manager extension links in
`common/home-base/pi.nix`; use the normal host build/switch workflow, then restart
Pi (or `/reload` once the main agent is idle). Do not overwrite store links or
install another copy with `pi install`.

```sh
cd common/home-base/pi
bun test extensions/btw/tests/*.test.ts
bun run test
```

Tests use fake model responses, not live credentials. Manual TUI smoke check:
start a normal long-running task, submit `/btw explain the last decision`, verify
the main task continues and a separate card appears; repeat with `/btw cancel`
and confirm only the side request stops. Reload the session and verify the card
is still visible.
