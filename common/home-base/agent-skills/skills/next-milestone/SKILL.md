---
name: next-milestone
description: Implement the next uncompleted milestone from plans/, ROADMAP.md, or any progress file, then audit it with the bundled reviewer agent, apply the fixes it reports, re-run the project's build/test/lint/fmt stack, mark the milestone done, commit the finished work, and present only the final verified diff stat plus a findings table. Use when asked to advance a roadmap, knock out the next TODO/milestone, or "do the next item."
---

# next-milestone

Implement the next uncompleted milestone, then review → fix → verify → mark done → commit → present a clean final diff.

Invoke as `/skill:next-milestone` (interactive) or let the model pick it up by description. To run it across a whole roadmap in one shot, see **Iterating over many milestones** at the bottom.

## Operating rules

- Track every step with the `todo` tool so progress is visible and resumable.
- Don't surface intermediate output — only the final block in the last step.
- Use native tools: `find` for file lookup, `read` for files, `search` for content. Never shell out to `find`/`ls`/`cat`/`grep`/`rg`.
- Do **not** delegate the review to a hand-written prompt — use the bundled **`reviewer`** agent via the `task` tool. It reads the diff, reports issues through `report_finding`, and yields a structured verdict.
- **Fan-out is optional and risk-gated.** Steps 1, 3, 5, 6, 7 stay single-author and sequential — never parallelize them. Only **Step 2** (broad milestones) and **Step 4** (high-risk diffs) may fan out, and only when the trigger named in that step fires. For small, local changes the plain path is faster and cheaper; the orchestration below is a net loss there.

## Step 0 — Seed the todo list

```
todo init, phases:
  Locate   → [Find progress file, Extract next milestone]
  Build    → [Understand codebase, Implement milestone]
  Review   → [Run reviewer agent, Apply findings]
  Verify   → [Run build/test/lint/fmt]
  Finish   → [Mark milestone done, Commit final state]
```

Mark each `done` as you go; the next task auto-promotes.

## Step 1 — Locate the next milestone

Find the progress file with `find`, in this preference order:

1. `find` for `plans/**/*.md` — read each, take the first uncompleted item.
2. `ROADMAP.md` at repo root.
3. `find` for `TODO.md`, `PROGRESS.md`, `MILESTONES.md`, `PLAN.md`, `docs/plan*.md`.

"Uncompleted" = an unchecked `- [ ]`, an unmarked heading, or `TODO`/`PENDING` status. Use `search` for `- \[ \]|TODO|PENDING` inside candidates to jump straight to it.

Extract the **first** uncompleted milestone only (top of file): its title, acceptance criteria/sub-tasks, and any prerequisites already marked done. Implement exactly one.

If the documented milestone is ambiguous — missing acceptance criteria, underspecified behavior, conflicting requirements, or multiple materially different implementations — **stop before editing**. Ask the user targeted questions and continue the discussion until all behavior, scope, non-goals, and verification details are settled. Do not implement by inference.

If no progress file exists, tell the user and stop.

## Step 2 — Understand the codebase + validation stack

Before editing:
- `read` the source files the milestone touches; `search` for the symbols involved.
- Determine the validation commands and **record them now** (used in Step 4), in priority order:
  1. `Justfile` / `Makefile` / `taskfile.yml` recipes named `build`, `test`, `lint`, `fmt`, `check` (`find` them, `read` the recipes).
  2. Language-native, e.g. Rust `cargo build && cargo test && cargo clippy && cargo fmt --check`; Go `go build ./... && go test ./... && golangci-lint run`; JS/TS `<pm> run build && <pm> test && <pm> run lint`; Zig `zig build test`.
  3. CI config (`read` `.github/workflows/*`, `.gitlab-ci.yml`) for the canonical list.

**Broad or unfamiliar milestone? (optional fan-out.)** When the milestone spans several subsystems and you don't already know the code, read in parallel with read-only scouts instead of serial `read`/`search` — drive it from one `eval` cell:

```py
M = {"type": "array", "items": {"type": "string"}}
SCHEMA = {"type": "object", "additionalProperties": False,
          "required": ["files", "symbols", "invariants", "commands", "risks"],
          "properties": {k: M for k in ["files", "symbols", "invariants", "commands", "risks"]}}
SCOUTS = [
  "Map the source files & symbols this milestone edits: <criteria>.",
  "Trace call sites / dispatch points for <symbols>; list the invariants they rely on.",
  "Find existing tests & fixtures for <area> and how they are run.",
  "Find the build/test/lint/fmt commands (Justfile/Makefile/taskfile, else CI, else language-native).",
]
maps = parallel([lambda p=p: agent(p, agent_type="explore", label="scout", schema=SCHEMA) for p in SCOUTS])
```

**You** merge the maps and record the single validation stack — don't offload that synthesis to an agent. Skip this for a one-file milestone; serial `read`/`search` wins there.

## Step 3 — Implement the milestone

Make the changes that satisfy the acceptance criteria, following existing style and module shape. No refactors or abstractions outside scope. Add tests only if the milestone introduces testable behavior. Do **not** mark the milestone complete yet. Leave changes unstaged so the reviewer's `git diff` sees them.

## Step 4 — Review → fix loop (the loop)

OMP has no declarative `Loop:` block; this is the native pattern — a bounded orchestrator loop around the `reviewer` subagent. Run **up to 2 rounds**:

**Spawn the reviewer** (`task` tool, batch shape):

```
task agent="reviewer"
  context: |
    Milestone: <title>
    Reviewing uncommitted changes for this milestone. Project conventions live in
    AGENTS.md / CONTRIBUTING (read them and enforce). Changes are unstaged; `git diff`
    shows them. Focus on correctness, safety, concurrency, API misuse, and convention
    violations introduced by THIS patch only.
  tasks:
    - assignment: |
        Review the current uncommitted diff for the "<title>" milestone. Read every
        changed file in full and trace new cross-boundary types to their dispatch points.
        Report each issue via report_finding, then yield your verdict.
```

The reviewer is read-only and returns a structured verdict:
- `overall_correctness`: `correct` | `incorrect`
- `explanation`, `confidence`
- `findings[]`: each `{ title, body, priority (P0–P3), confidence, file_path, line_start, line_end }`

**Apply findings** in priority order (P0 → P3); within a priority, highest confidence first. Batch findings in the same function. Make only the change each finding describes. If a finding is a genuine false positive given surrounding code, keep it for the summary as "Reviewed, not applicable" — don't silently drop it.

**Loop condition:** if you applied any fix that changed logic, spawn the reviewer once more (round 2) on the new diff. Stop when `overall_correctness: correct`, or no remaining P0/P1, or after round 2 — whichever comes first. (For follow-up rounds you can `irc` the same reviewer instead of a fresh spawn — it already holds context.)

### High-risk mode (optional — gated on risk)

Use the default single-reviewer loop above for local, low-risk diffs. Switch to this panel **only** when the diff trips a risk signal: it touches a **security / trust boundary**, **concurrency / async**, a **data migration or schema change**, a **broad call-graph or public-API change**, or Step 5 has **failed twice** on this milestone. For a one-file fix the panel is pure cost — don't.

Drive it from one `eval` cell. The bundled `reviewer` runs as one lens among several; **you** dedupe and own the final call — panel members never patch the diff.

```py
# VERDICT = the same shape the reviewer yields: overall_correctness, explanation, confidence, findings[]
DIFF = "the uncommitted diff for milestone <title> (run `git diff`)"
LENSES = [
  ("canonical",   "Review THIS patch for any issue. " + DIFF),
  ("correctness", "ONLY correctness / data-flow / edge cases / broken invariants. " + DIFF),
  ("security",    "ONLY trust-boundary / injection / authz / secret-leak issues. " + DIFF),
  ("concurrency", "ONLY races / lifetimes / reentrancy / ordering. " + DIFF),
  ("convention",  "ONLY project-convention & API-misuse issues (read AGENTS.md first). " + DIFF),
]
reviews  = parallel([lambda l=l: agent(l[1], agent_type="reviewer", label=f"rev:{l[0]}", schema=VERDICT) for l in LENSES])
findings = [f for r in reviews for f in r["findings"]]
# >>> YOU dedupe findings here by (file_path, nearby line, same root cause). <<<

# Adversarially verify only what matters: every P0/P1, plus low-confidence P2.
REF = {"type": "object", "additionalProperties": False, "required": ["verdict", "rationale"],
       "properties": {"verdict": {"enum": ["survives", "refuted"]}, "rationale": {"type": "string"}}}
def survives(f):  # 3 skeptics, each told to refute from code; default 'refuted' when unsure
    votes = parallel([lambda i=i: agent(
        f"Try to REFUTE this finding from concrete code evidence. Return 'refuted' if you "
        f"cannot prove it is a real bug, or are unsure.\nFinding: {f['title']} @ "
        f"{f['file_path']}:{f['line_start']}\n{f['body']}",
        agent_type="oracle", label=f"refute#{i}", schema=REF) for i in range(3)])
    return sum(v["verdict"] == "survives" for v in votes) >= 2

def hot(f):  return f["priority"] in ("P0", "P1") or (f["priority"] == "P2" and f["confidence"] < 0.6)
confirmed = [f for f in findings if not hot(f) or survives(f)]
```

Then **you** (one author) apply `confirmed` in priority order exactly as the default loop describes, record refuted findings as "Reviewed, not applicable" (don't silently drop them), and run the bounded round-2 reviewer if a logic-changing fix landed.

## Step 5 — Verify

Run the full validation stack from Step 2 with `bash`. Every command must pass. On failure: fix it, then re-run the **entire** stack from the top. Don't proceed until clean.

## Step 6 — Mark the milestone done

In the Step 1 file, flip `- [ ]` → `- [x]` (or set `Status: done` if the file uses that style). Use `edit` for the single-line change; touch nothing else.

## Step 7 — Commit final state

Use the `commit` skill as the last workflow step. Commit only after Step 6 is complete and the working tree contains the milestone implementation, reviewer fixes, validation updates, and progress-file completion mark. Follow the project's commit-message conventions; if the commit skill reports that no safe agent-authored commit can be made, stop and report the exact blocker.

After the commit succeeds, print only this final block:

```
## Milestone: <title>

### Commit
<commit hash and subject>

### Changes
<output of: git show --stat --oneline --no-renames HEAD>

### Review findings
| # | Priority | Conf | Location | Issue | Resolution |
|---|----------|------|----------|-------|------------|
| 1 | P1 | 0.8 | src/foo.rs:42 | ... | Fixed / Not applicable |
(If none: "Reviewer found no issues.")

### Verified
Build ✓  Tests ✓  Lint ✓  Fmt ✓
```

Do not print build logs, the full diff, step narration, or the reviewer's raw transcript. The user can run `git show --stat HEAD` for the committed diff; the reviewer transcript is at `history://<reviewer-id>`.

---

## Iterating over many milestones

This skill does **one** milestone. To advance several, use an OMP-native outer loop:

- **`/loop`** — re-submits `/skill:next-milestone` each iteration. `loop.mode` (`prompt | compact | reset`) controls what happens between iterations (`compact`/`reset` keep context from ballooning across milestones).
- **Goal Mode** (`goal.enabled`, `goal.continuationModes`) — set a goal like "complete all unchecked roadmap items"; the session auto-continues between turns until it's met.
- **`eval` `agent()` / `pipeline()`** — drive it programmatically when milestones are independent:
  ```py
  # one isolated subagent per milestone, bounded fan-out
  results = parallel([lambda m=m: agent(f"Run next-milestone for: {m}") for m in milestones])
  ```
  Use `pipeline(items, *stages)` instead when each milestone depends on the previous one (barrier between stages).
