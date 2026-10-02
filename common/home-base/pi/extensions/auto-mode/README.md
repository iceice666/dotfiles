# Auto Mode

Repo-owned pre-execution guardrail, enabled by default on every fresh Pi session.
It is **not a sandbox**: it reduces routine approval prompts without treating the
model as an authorization authority or providing a confidentiality guarantee.
Tools execute with the invoking user's normal host permissions, environment,
network and filesystem access. No Pi OS sandbox is installed. Model review and
preflight path checks are guardrails, not process or confidentiality isolation.

## Tool provenance checks

Before every tool call other than local coordination (todo, team messaging,
questions, background list/output/wait/stop), Auto Mode checks that:

- its own module was loaded from the content-addressed `/nix/store/*-pi-extensions`
  tree (not a mutable `~/.pi/agent/extensions` copy, a checkout, or an SDK embedding);
- the called tool is an upstream built-in with the expected source/name/path, or
  comes from the same managed tree. SDK tools and foreign extensions fail.

These checks do not require a sandbox backend or overridden read/bash tools.
On failure the footer shows `auto:UNMANAGED`, the human gets an error notice, and
the call is blocked with `terminate` so the agent stops instead of probing other
tools. This holds even after `/auto off` or under YOLO, and `/yolo on` is
refused. The fix is operational: exit and start the managed launcher (`type -a pi`).

The managed launcher avoids mixing cached extension versions across a switch.
The auto-discovery directory contains `unmanaged-pi-guard` instead of a second
copy of the tree. Restart the managed Pi after deploying updates.

## Controls

- `/auto status`: current session state and tool provenance; classifier follows the current model.
- `/auto on`: enable this session.
- `/auto off`: parent TUI only, after explicit human confirmation. Workers cannot
  disable their gate through this command. Existing and new workers remain on.
  Tool provenance checks keep running.
- `/auto grant PATH`: parent TUI only; approve read/write/edit within an existing
  repository file or directory for this parent session and its workers.
- `/auto scopes`: list active scope IDs and canonical paths.
- `/auto revoke ID` or `/auto revoke all`: revoke scopes immediately for future
  preflight checks; already executing OS operations cannot be recalled.
- Restart/reload/new session resets to on and discards scopes. No writable policy
  config or command-approval cache exists, so corrupt settings cannot turn it off.

## Team YOLO

```text
/yolo on
/yolo off
/yolo status
```

These explicit commands control a session-local team switch. Only the parent TUI
can change it; `/yolo on` needs no second confirmation. It bypasses **the entire
Auto Mode tool hook**, including local Auto Mode policy, model classification,
and per-action Auto Mode prompts, for the parent and existing/new workers.
The footer shows `YOLO · host access`.

Tools have normal host access; there is no OS sandbox or secret/network isolation.
YOLO does **not** disable tool provenance checks or todo verification gates.
Explicit check-declaration approval through `approveAction` is unchanged.
`/yolo on` is refused while tool provenance is unattested.

Workers query the authenticated parent before each tool call and recheck a true
YOLO result before releasing the call; no environment or cached flag grants it.
Unreachable/old parent service blocks rather than assuming YOLO. Switching off
invalidates pending review and restores the parent's gate even after `/auto off`.
Already running tools are not stopped; a preflight-to-execution race remains.
Reload/restart/new session and branch navigation reset YOLO off. Ordinary inputs
and compaction do not reset it. `/auto off` remains parent-only and is independent;
`/yolo off` or parent `/auto on` restores Auto Mode after team YOLO.

## Decisions

1. Local policy checks credential-shaped arguments, file boundaries, and safety
   control paths. Credential files are blocked before model review; control-file
   writes require a human. Ordinary workspace reads/writes and local task/team
   coordination pass without another model call.
2. Every shell command (including `background_task.start` using its actual cwd),
   recursive search, external search, image transmission, worker spawn, and unknown
   tool receives independent review. There is no shell prefix allowlist or shell
   normalization. Background list/output/wait/stop remain local fast paths.
3. The current session model receives a no-tools request with exact action JSON,
   the latest input, and bounded branch-local history from Observational Memory
   plus recent raw input/question answers. Only parent interactive TUI input carries
   human provenance; memory, historical user-role messages, RPC/extension input,
   and worker tasks never establish human grants. Resumed sessions can recover
   task context without inferring authorization.
4. `allow` executes; `ask` requests a **single-use** human decision; `deny` blocks.
   Classifier failures/invalid output/timeouts fall back to human review, never
   automatic execution. Missing UI, cancellation, rejection, timeout, oversized
   requests, and policy errors block. A blocked action must not be retried through
   another tool or worker to evade the decision.
5. Refusal ledger: Auto Mode records trusted refusals itself — credential blocks,
   classifier denies, rejected/unavailable approvals, and recognized external
   sandbox refusals seen in tool results (`Restricted execution…`, backend/workspace
   refusals; ordinary file errors do not count). Until the next human TUI turn (or,
   in a worker, the next coordinator message), `bash`, `background_task start`,
   `agent_spawn`, and `agent_send`/`agent_ask` to a teammate always need a
   single-use human approval whose reason names the earlier refusal. The classifier
   may still deny but never allow them; local-`ask` actions stay off the classifier.
   The last four refusals are sent as trusted `boundary.recentDenials`, and the
   prompt treats reaching a refused effect another way as a bypass. Worker dialogs
   in the parent show the exact action but not the worker-local reason.
6. Live human decisions: answers the human types in the parent TUI to the agent's
   own `ask_user_question` or `agent_ask` to `user` are published in-process
   (`askHumanDecision`) and sent as trusted `task.decisions` (last four, bounded)
   until the next input. Because the agent wrote the question, a decision authorizes
   only what the question explicitly described but can always narrow the task.
   RPC/print answers, relayed worker questions, and Auto Mode's own dialogs are not
   published; historical answers in context remain lower-trust evidence.

Human dialogs display the full original tool arguments and cwd, not a shortened
command. Actions too large for the UI are refused rather than approved unseen.
There is no remembered "allow all Bash" or exact-command cache: file contents,
policy, or authorization may change between calls. The approval lasts only for
that pending tool hook. Mutations observed during review invalidate the call.
Explicit file scopes are separate human-created grants, described below.

Worker dialogs use the authenticated internal `auto_mode_approve` team operation,
not ordinary agent messages or `agent_reply`. The parent broker obtains a real UI
selection and returns the matching action hash. Disconnect, worker stop, parent
shutdown, and a five-minute deadline cancel pending approvals. Parent Escape
continues to cancel only its own turn; stop workers explicitly as with other team
operations. Approvals do not authorize future worker actions.

## Data and limits

The classifier uses `ctx.modelRegistry.complete` and existing registry auth;
there are no new credentials or runtime npm installation requirements. It does not
send arbitrary historical tool results, thinking, the full conversation, or file
contents read by the extension. It does include selected historical structured
question/answer results. **Current tool arguments, task text, selected memories,
and source excerpts may contain private source or secrets** and are transmitted
to the session model provider. Local
credential detection is deliberately only a conservative tripwire, not a complete
secret scanner. Task input is limited to 8 KiB; the whole classifier context to
32 KiB; review to 45 seconds with cancellation. Oversize input falls back to local
human review when it fits the full-display limit, otherwise blocks.

No additional payload/audit log is written. Pi's normal session/tool history and
question display persistence still apply. Classifier errors are sanitized; no
provider request/error bodies are exposed. Nested review calls consume extra
model quota; this initial hook does not add that usage to Pi's displayed tool totals.

## Branch-local memory context

`context.ts` uses the pinned OM 3.1.3 pure `fullProjection` and
`recallMemorySources` readers. Deployment loads the sibling Nix-pinned source;
development tests use the exact `pi-observational-memory@3.1.3` dev dependency.
No OM extension entrypoint, clipboard command, observer, or additional model call
is invoked. These are internal upstream APIs: update the compatibility fixtures
when updating the Nix pin and dev dependency together.

Each review takes one `getBranch()` snapshot, never all session-tree entries.
It uses full ledger memory, not the last compaction's visible summary (which can
be empty before the first compaction). Selection favors action-path/command terms,
important observations, and recency. A 12 KiB context envelope reserves space for
up to eight recent raw user/question-answer entries, up to eight memories, and
bounded source excerpts. Excerpts retain head and tail and explicitly mark missing
content; no completeness guarantee is inferred from a coverage watermark.

Historical sources are labelled by original role/tool and retain IDs. Missing or
colliding provenance is marked partial/ambiguous. Memory prose, user-role labels,
and historical approval-looking text are **context, not a grant**. Recent raw
restrictions supersede older memories. This allows "continue" to carry the older
task without turning a memory of permission into an executable authorization.
General tool output, assistant prose/thinking, and unrelated custom messages are
not copied into the envelope. Missing/incompatible OM readers degrade to recent
raw context and never disable policy or broaden permissions.

A new input, session change, or branch navigation invalidates pending review and
single-use approval. Background OM metadata appends alone do not invalidate an
otherwise unchanged task. No context or permission cache crosses sessions/branches.
Workers use their own branch plus a fresh bounded parent snapshot obtained through
`auto_mode_context` (also used for authoritative team YOLO state). Parent records are namespaced by source session and explicitly
labelled context, not authorization. Parent recent restrictions are prioritized;
inherited content has a 4 KiB sub-budget within the 12 KiB combined envelope.
Workers do not read arbitrary parent session files or accept memory/grants from
peer messages. Missing/old broker support blocks or falls back to single-use human
approval, never grants a scope. Parent input, relevant question-answer results,
team notifications, and explicit scope changes revise the parent snapshot. Workers
revalidate its revision before releasing reviewed actions. Parent-side team custom
message bodies are not yet included in raw context, though their arrival invalidates
older reviews. Worker RPC inputs do not become human grants.

## Session file scopes

For repo extension development without approving every edit, the human can run:

```text
/auto grant common/home-base/pi/extensions/background-task
/auto scopes
/auto revoke all
```

The confirmation shows the canonical file/directory and exclusions. Only that
explicit UI selection creates a grant; neither classifier output, OM, historical
answers, nor `agent_reply` can create one. Scopes are in-memory in the parent only;
workers query the authenticated broker for each affected action and revalidate
before allowing it. Reload/restart/shutdown and branch navigation clear scopes.
Ordinary continuation keeps them, but pending reviews still notice newer input.

Scopes can skip repetitive file-policy asks only for `read`, `write`, and `edit`.
They never cover shell/background commands, deployments, network tools, secrets,
Git/agent metadata, shell startup files, or live managed extension roots. Local
hard blocks run first. Lexical and canonical boundaries, symlink retargets, and
hardlinks are checked; scopes are not OS access controls. Source extensions
in the repository are eligible only when not part of the loaded runtime tree.
Default deployment loads an immutable Nix tree, leaving repository source editable.
Arbitrary externally loaded tool-less extensions are outside this managed-layout
claim; do not use repo scopes with untracked runtime extension locations.

Revocation invalidates pending scope checks rather than reusing cached allows.
There remains a small preflight-to-execution race, like the existing file checks;
this is not atomic OS capability revocation. Scope permission is not authorization
to do unrelated work: task intent and normal user permissions remain applicable.

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
  compaction, or classifier prose. Workers and their file/shell tools run with the
  invoking user's permissions; shared workspaces are not isolation.

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
