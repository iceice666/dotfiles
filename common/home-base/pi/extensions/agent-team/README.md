# Pi Agent Team

Global Pi extension: independent, persistent Pi RPC workers with peer messaging,
nonblocking questions, and an append-only shared board. Human questions use the
sibling `extensions/ask-question/service.ts` shared UI; keep both extension directories installed.

## Enable

Run `/reload` in Pi. Ask, for example:

> 建立 researcher 和 reviewer 兩個 agent。researcher 研究架構並寫入留言板，
> reviewer 讀取研究結果後檢查風險。有問題用 agent_ask 問我這個父 agent。
> 先不要修改程式碼。

The parent receives child final responses and questions automatically. Workers stay
alive after completing a task, preserving their context for subsequent messages.
Only the parent gets `agent_spawn` and `agent_stop`.

## Tools

| Tool | Purpose |
| --- | --- |
| `agent_spawn({name, task, cwd?, model?, thinking?})` | Spawn a worker; returns on task acceptance, not completion |
| `agent_list({})` | Worker states, session paths, archive directory |
| `agent_wait({agent, timeout?})` | Event-driven wait for worker idle; default 60 seconds, maximum 86400 |
| `agent_send({to, message})` | Send to a sibling or `parent`; wakes idle recipients |
| `agent_ask({to?, question, options?, multiSelect?, header?})` | Default: tracked question to `parent`; explicit `to: "user"`: real human UI |
| `agent_reply({question_id, answer})` | Answer a question addressed to you |
| `agent_inbox({after?, limit?})` | Paginated sent/received history |
| `board_post({topic, body, reply_to?})` | Append shared information; no automatic notifications |
| `board_read({topic?, after?, limit?})` | Paginated shared notes |
| `agent_stop({agent})` | Stop worker and process group |

### Readable tool and message cards

`agent_*` and `board_*` calls/results use compact TUI cards: operation, recipient,
state, and message preview instead of raw JSON. Automatic worker messages use the
same presentation and retain their agent-data provenance label. Long results are
collapsed by rendered line count; use Pi's tool expansion shortcut (default
`Ctrl+O`) for full text, question IDs, session paths, and pagination/archive metadata.
Acceptance, idle, and cancelled/unavailable human answers are explicitly distinct
from task success or authorization. JSON sent to the model and RPC clients is unchanged.
Saved JSON results and older automatic messages also render with these cards.

### Waiting for a worker

Parents and children can call `agent_wait` with a worker name (not themselves or
`parent`). It returns immediately for an already idle/stopped/failed worker;
otherwise it waits for Pi's `agent_settled`, not intermediate final text or
`agent_end` during automatic retries. Accepted new messages mark workers running
before their RPC `agent_start` event arrives. Idle means this run settled, **not**
proof that the requested task succeeded. Read automatic results or `agent_inbox`
and verify the work independently.

The result includes `agent`, `status`, `reason` and the session path when known.
Reasons are `idle`, `question`, `blocked`, `stopped`, `failed`, `timeout`,
`cancelled`, `caller_stopped`, or `closed`. Outstanding questions from the target,
or addressed to the caller, return promptly with `question_id` and `question_to`;
read the question with `agent_inbox` and answer with `agent_reply` when addressed
to you. A human question remains exclusively for the real user. Questions to
other agents are not human authorization. Waiting cycles are rejected.

Timeout is a positive number of seconds, defaults to 60, and is capped at 86400.
Escape cancels only the wait, never the worker. Session shutdown releases waits;
child HTTP disconnects remove broker waiters. No polling or extra worker prompts
are used. You can continue other work instead of waiting; notifications still
arrive automatically. Do not use repeated short waits as a polling loop.

### Footer selection and read-only attach

- `/team` or `/team status`: textual metadata, including stopped workers (also available outside TUI).
- With an empty editor, `↓` selects a live worker in the status-line footer; `↑` / `↓` selects workers, `Enter` opens its full-terminal, borderless transcript, and `Esc` returns to the editor.
- `/team attach NAME`: directly open that worker's transcript.
- In the fullscreen transcript: mouse wheel / trackpad, `↑` / `↓` (or `k` / `j`), `PageUp` / `PageDown`, `Home` scroll; `End` or `f` follows new output again. Manual scrolling pauses follow.
- Regular Pi temporarily enables SGR mouse reporting while the viewer is open and disables it on exit. Fullscreen Pi uses its existing normalized mouse dispatch. Terminal-dependent mouse reporting must be supported; keyboard scrolling remains available.
- `Ctrl+O`: expand/collapse tool output. `Ctrl+T`: hide/show thinking.
- `Esc` / `q` / `Ctrl+C`: close the transcript and return to the editor.

The fullscreen read-only transcript refreshes every 150 ms and is rendered with Pi's own `UserMessageComponent`, `AssistantMessageComponent`, and
`ToolExecutionComponent`: Markdown, code highlighting, thinking, native built-in
tool cards, recorded edit diffs, and streaming results—not flattened raw event text.
The architecture follows oh-my-pi's separate `AgentTranscriptViewer` /
`ChatTranscriptBuilder` approach, adapted to this Pi version's public APIs.

Only thinking exposed by the provider can be shown. Images are not rendered in this
scrolling viewer. Built-in and repo-owned team tool renderers are reused; other child-only custom
extension renderers cannot be transported over RPC and use a generic expandable tool card.
Edit previews use recorded diffs, never re-read current files to reconstruct history.

Attach is **observation only**: no session switch, prompt, steer, abort, or stop is
sent to the worker. Typed text is ignored. Closing/detaching leaves all workers
running. The native viewer keeps up to 500 recent records within a 1 MiB structured
data budget (separate from the legacy 256 KiB plain-text observation); truncation is labelled and
the worker's session path is displayed for inspecting older persisted history.
Stopped workers remain viewable until the parent session is reloaded/replaced.
Checking an empty team does not create a broker or worker.

`/team stop NAME` and `/team stop all` stop workers without LLM requests.
The status-line footer shows live workers, including idle workers; stopped and
failed/exited workers disappear from the footer but remain accessible by named
attach and `/team`. No separate above-editor team widget, picker overlay, or
team shortcut is installed. The team publishes state through `agent-team:state`,
answers `agent-team:request-state`, and handles `agent-team:attach` events so
status-line owns footer rendering and selection. Shutdown clears the published state.
User Escape aborts the current parent turn, **not** all independent worker work.
Use `/team stop all` to stop that work.

Agent-to-agent questions return immediately. A blocked agent should end its turn, not poll or
hold a tool call open. Replies start/continue its next turn. Busy recipients receive
messages via Pi steering at a tool boundary, not mid-tool interruption. Receipt
means accepted into Pi's queue, not proof the model has consumed the message.

### Asking the real human

`parent` means the coordinator **agent**, not the person using Pi. Use explicit
`to: "user"` when a decision or authorization must come from the real person:

```json
{"to":"user","question":"Which environments should I test?","options":[{"label":"Staging","description":"No production traffic"},{"label":"Local"}],"multiSelect":true}
```

Options are optional; users can always enter custom text. In the parent session,
this call waits for `{status, answers}` directly without starting a team or HTTP
listener. Each answer contains `question`, `selected` labels, and optional
`customText`. In a child, HTTP returns `{id, question_id, status:"pending", from,
to:"user"}` immediately (the 35-second transport timeout never waits for a human).
The broker later wakes that child with a tracked reply containing the same
structured answers. Only UI answers receive `from:"user", origin:"human"`;
`agent_reply` cannot answer a question addressed to the user. Both `user` and
`parent` are reserved worker names. Question/options remain agent-provided data;
only the human's submitted answer is human input.

`cancelled` and `unavailable` results have empty answers and never imply approval.
No-UI modes return unavailable; RPC uses native dialogs and TUI uses the shared
question panel. Standalone `ask_user_question` and team questions share one FIFO.
Stopping a child cancels its active/queued questions; shutdown/reload aborts all
team questions and prevents stale answers from reaching a replacement session.
HTTP validates question fields before queuing. Question requests are limited to
24,000 serialized characters, 12 options, and 12,000 characters per question.

## Defaults and lifecycle

- At most 4 live workers (including idle/waiting workers).
- Model and thinking level inherit from parent at spawn time; changes to the parent
  later do not alter existing workers. `model` override uses `provider/model`.
- Independent context: parent conversation is not cloned. Put necessary context in `task`.
- Default cwd is the parent's. Pass an **existing** worktree path for isolated edits;
  the extension does not create worktrees or merge changes.
- Same-directory workers inherit the parent's project trust decision. An alternate
  cwd starts with `--no-approve` so temporary trust is not silently extended.
- Workers reuse global Pi configuration, credentials, skills and extensions. Runtime-only
  provider registrations/CLI extension choices in the parent are not copied.
- Worker UI dialogs are cancelled, never auto-approved. Use `agent_ask` for ordinary
  coordination; requests requiring human authorization must use explicit `to: "user"`.
- Worker final text is forwarded automatically; explicit progress messages are optional.
- `/reload`, new/resumed/forked sessions, or parent shutdown stop the current team.
  Child startup cancellation also stops the partial child. Workers check parent PID
  liveness every 2 seconds to mitigate abrupt parent crashes.
- On macOS/Linux stopping signals the worker process group, with SIGKILL fallback.
  Windows currently stops only the direct child; descendant cleanup is not guaranteed.

## Persistence

Archives are stored privately beneath:

```
~/.pi/agent/teams/<parent-session-id>/<team-run-id>/
  events.jsonl       # messages, acceptance/failure receipts, questions, replies, posts
  team.json          # final team metadata on graceful shutdown
  <worker-name>/    # Pi's own session JSONL files
```

`PI_CODING_AGENT_DIR` is respected. A fresh team-run ID prevents simultaneous sessions
from corrupting each other's archives. **There is no automatic replay or recovery**:
after reload/restart, previous archives remain readable with Pi's normal file tools,
but the new team's board is empty. Pi sessions can be inspected/resumed manually.
Team board history is external state; navigating `/tree` does not roll it back.

One authenticated localhost HTTP broker owns all board writes, so simultaneous posts
do not perform racing read-modify-write updates. Each child gets an independent random
bearer token identifying the sender; the token is revoked on stop. Tokens are not written
to the archive. No network listener or worker is created until a team tool is used.

Messages/posts are limited to 12,000 characters. Read tools paginate (default 10,
maximum 50 items), with an approximate 40KB page budget; large automatic result texts
are truncated in model delivery and retained fully in `events.jsonl`.
RPC uses LF-only JSON framing and handles split UTF-8 chunks, correlated responses,
request timeouts and process exits. No shell interpolation is used for spawning.

## Safety / limitations

This is **not a sandbox or security boundary**. Workers have the same account and
filesystem/network capabilities as Pi. A hostile process with those permissions can
read environment tokens or modify files. Coordinate file ownership or use worktrees.
Agent messages are labelled as agent data, not user/system instructions.

Each worker can incur model costs and trigger parent responses; there is no aggregate
spending limit or guaranteed loop prevention. Prompt rules discourage acknowledgment
loops, but use `/team stop all` if collaboration becomes unproductive. Child usage is
recorded in child sessions, not added to the parent's usage totals. Arbitrary extensions
that log non-JSON to RPC stdout can break transport. A daemon deliberately escaping
its process group is not guaranteed to be killed.

Override `PI_TEAM_EXECUTABLE` with an executable path if `pi` is not in PATH.
`PI_TEAM_URL`, `PI_TEAM_TOKEN`, `PI_TEAM_AGENT`, and `PI_TEAM_PARENT_PID` are internal
worker environment variables; do not set them manually.

## Verify (no paid model calls)

```bash
cd common/home-base/pi # from the dotfiles checkout
bun install --frozen-lockfile --ignore-scripts
node --test extensions/agent-team/tests/*.test.mjs
bun test extensions/agent-team/tests/*.test.ts
```

Requires Node 22.19+ and Bun. Tests use the pinned local Pi 0.85.1 development SDK,
not a global installation. The two legacy real-Pi smoke tests are skipped: they
inherit personal configuration and do not have an isolated, fail-closed provider
fixture. `--offline` alone does not prohibit completion API calls. No live model
or credentials are needed for the enabled tests.
Unit tests cover messaging, questions, pagination, authentication, LF framing,
errors and timeout handling. Live model decision-making is not tested by this suite.
