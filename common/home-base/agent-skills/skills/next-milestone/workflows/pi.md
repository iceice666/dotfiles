# Pi tool mapping

Read `../SKILL.md` relative to this file for the canonical next-milestone workflow.
This adapter maps its steps to Pi; it does not change scope, review limits,
verification requirements, authorization, or final-only output. Invoke with
`/skill:next-milestone`; no separate prompt template is required.

## Step 0 — progress tracking

Use the repo-provided `todo` extension. Add phase tasks with `action: "add"`
and `items`, using `category` for Locate, Build, Review, Verify, and Finish.
Use `action: "update"` with the returned task ID to set `in_progress` or
`completed`. Mark tasks complete only after their required evidence exists.
If the extension is unavailable, keep a short internal checklist instead.

## Steps 1–3 — exploration and implementation

Use `read`, `edit`, and `write` for file contents. Search with `grep`, `find`,
or `ls` if enabled; otherwise use `bash` with `rg`, `find`, and `ls`.
Pi's `read` is not a web browser. Use `web_search` for public external research
when available, without sending private code or secrets in queries.

For the optional broad-milestone scouts, use `agent_spawn` with unique names,
a self-contained task, and an explicit `cwd`. Assign read-only exploration
of distinct areas; the parent synthesizes their results and remains the sole
implementation author. Pi workers do not inherit the parent's conversation,
and a shared cwd is not a sandbox or a separate worktree.

## Step 4 — review

Use a fresh `agent_spawn` worker, not an assumed built-in reviewer agent.
Give it the milestone title, acceptance criteria, project instructions,
changed file list, and exact diff scope. Ask for a read-only review of the
milestone's changes, with P0–P3, confidence, path, line range, explanation,
and an overall correct/incorrect verdict. No fixes or commits by the reviewer.

Normally changes are unstaged and `git diff` shows them. If new files had to
be staged for Nix evaluation, explicitly include those files and their staged
diff in the review brief. Inspect `git status`, `git diff`, and
`git diff --cached`; never let unrelated pre-existing changes enter the review
or final commit merely because they are staged.

`agent_spawn` returns acceptance, not completion. Results arrive asynchronously;
continue independent work or end the turn if waiting. Do not poll
`agent_list`/`agent_inbox`, restart a healthy reviewer, or invent a wait tool.
Use `agent_reply` for tracked questions and `agent_send` for review follow-ups.
Retain the reviewer for the skill's bounded second round; stop unused workers
with `agent_stop` once their assignment is complete.

For high-risk review panels, respect the four-live-worker limit. Run the five
lenses in bounded batches, releasing finished workers before spawning more.
Do the same for the three independent skeptics per important finding. The
parent deduplicates findings, decides applicability, and applies fixes.
When delegation is unavailable, use the canonical skill's distinct local
review fallback and state that limitation honestly.

## Steps 5–7 — verify and finish

Use `background_task` for long builds/tests and inspect its output after
completion; do not busy-poll. Tool acceptance or a running job is not a pass.
A failed check requires the canonical fix-and-rerun loop before marking done.
If no background tool is available, use `bash` with an appropriate timeout.

Ask for actual human decisions with `ask_user_question` or
`agent_ask` with `to: "user"`. A worker must route human questions through
`agent_ask`; the default recipient is its parent, not the human. Cancelled or
unavailable answers never authorize an action.

Read the shared `commit` skill before committing. The parent performs the
completion mark and final commit, then emits only the canonical final block.
For multiple milestones, finish and verify one before starting the next;
Pi has no assumed OMP `/loop`, `eval`, or goal-mode API.
