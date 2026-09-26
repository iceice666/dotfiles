# Auto Mode

Repo-owned pre-execution guardrail, enabled by default on every fresh Pi session.
It is **not a sandbox**: extensions, subprocesses, and the agent share the user's
permissions. It reduces routine approval prompts without treating the model as
an authorization authority or providing a confidentiality guarantee.

## Controls

- `/auto status`: current session state; classifier follows the current model.
- `/auto on`: enable this session.
- `/auto off`: parent TUI only, after explicit human confirmation. Workers cannot
  disable their gate through this command. Existing and new workers remain on.
- Restart/reload/new session resets to on. No writable policy/config or approval
  cache exists, so corrupt settings cannot silently turn protection off.

## Decisions

1. Local policy checks credential-shaped arguments, file boundaries, and safety
   control paths. Credential files are blocked before model review; control-file
   writes require a human. Ordinary workspace reads/writes and local task/team
   coordination pass without another model call.
2. Every shell command (including `background_task.start` using its actual cwd),
   recursive search, external search, image transmission, worker spawn, and unknown
   tool receives independent review. There is no shell prefix allowlist or shell
   normalization. Background list/output/wait/stop remain local fast paths.
3. The current session model receives a no-tools request with exact action JSON
   and the latest input context. Only parent interactive TUI input carries human
   provenance; RPC/extension input and worker tasks do not establish human grants.
   Resumed sessions start with no inferred authorization until new input arrives.
4. `allow` executes; `ask` requests a **single-use** human decision; `deny` blocks.
   Classifier failures/invalid output/timeouts fall back to human review, never
   automatic execution. Missing UI, cancellation, rejection, timeout, oversized
   requests, and policy errors block. A blocked action must not be retried through
   another tool or worker to evade the decision.

Human dialogs display the full original tool arguments and cwd, not a shortened
command. Actions too large for the UI are refused rather than approved unseen.
There is no remembered "allow all Bash" or exact-command cache: file contents,
policy, or authorization may change between calls. The approval lasts only for
that pending tool hook. Mutations observed during review invalidate the call.

Worker dialogs use the authenticated internal `auto_mode_approve` team operation,
not ordinary agent messages or `agent_reply`. The parent broker obtains a real UI
selection and returns the matching action hash. Disconnect, worker stop, parent
shutdown, and a five-minute deadline cancel pending approvals. Parent Escape
continues to cancel only its own turn; stop workers explicitly as with other team
operations. Approvals do not authorize future worker actions.

## Data and limits

The classifier uses `ctx.modelRegistry.complete` and existing registry auth;
there are no new credentials or dependencies. It sends no historical tool results,
full conversation, or file contents read by the extension. However, **the current
write/edit payload or tool arguments and current task text may contain private
source or secrets** and are transmitted to the session model provider. Local
credential detection is deliberately only a conservative tripwire, not a complete
secret scanner. Task input is limited to 8 KiB; the whole classifier context to
32 KiB; review to 45 seconds with cancellation. Oversize input falls back to local
human review when it fits the full-display limit, otherwise blocks.

No additional payload/audit log is written. Pi's normal session/tool history and
question display persistence still apply. Classifier errors are sanitized; no
provider request/error bodies are exposed. Nested review calls consume extra
model quota; this initial hook does not add that usage to Pi's displayed tool totals.

## Boundaries and deliberate limitations

- It guards agent tool calls, not user `!`/`!!`, arbitrary extension internals, or
  everything a permitted process does later. Trusted extensions can mutate inputs
  after this hook; do not load untrusted extensions and claim enforcement.
- Filesystem checks are preflight checks, not atomic OS access control. Concurrent
  processes can change files/symlinks afterward. SDK file URLs/Unicode-space path
  aliases, dangling symlinks, and nonexistent exact read paths (which Pi might
  resolve through macOS filename fallbacks) are rejected rather than ambiguously reviewed.
- Routine workspace edits can overwrite existing files. This gate does not track
  ownership of pre-existing user work, Git dirty state, or recover lost content.
- Recursive shell/script behavior, external data egress, and user-intent alignment
  remain probabilistic classification. Scripts and tool implementations are not
  read by the reviewer. No shell parser or complete process/network mediation is
  claimed. Requests lacking evidence should produce `ask`.
- Coordination fast paths can wake workers, but do not grant permissions; each
  worker independently reviews its tools. Messages can reach teammate model
  providers; "local coordination" does not imply zero external disclosure.
  Tool fast paths assume repo-owned tools
  and built-ins retain their documented semantics.
- No durable consent ledger is inferred from agent messages, session roles,
  compaction, or classifier prose. Default-on workers are not sandboxed.

## Validation

From `common/home-base/pi`:

```sh
bun test extensions/auto-mode/tests/*.test.ts
node --test extensions/agent-team/tests/auto-mode-approval.test.mjs
bun run test
```

Tests use fake model responses and temporary files only: raw multiline commands,
background cwd, no approval cache, strict classifier output, failures/deadlines,
path escape/symlinks, external searches, exact human selections, and authenticated
worker approval cancellation. The pinned Pi loader is tested without model calls.

Before relying on it operationally, use a disposable project and test normal
editing, an intentionally ambiguous command, a child asking approval, rejecting
and cancelling that approval, and an unavailable classifier. Do not test using
real destructive commands or secrets. Live provider/TUI behavior needs human smoke
validation after deployment. All Pi-enabled hosts receive the source via the
existing recursive Home Manager extension tree; deployment is a separate action.
