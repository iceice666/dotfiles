---
name: next-milestone
description: Implement the next uncompleted milestone from plans/, ROADMAP.md, or any progress file, then audit it with a fresh reviewer pass, apply the fixes it reports, re-run the project's build/test/lint/fmt stack, mark the milestone done, commit the finished work, and present only the final verified diff stat plus a findings table. Use when asked to advance a roadmap, knock out the next TODO/milestone, or "do the next item."
---

# next-milestone

Implement the next uncompleted milestone, then review → fix → verify → mark done → commit → present a clean final diff.

Invoke this skill directly, or let your agent pick it up by description. To run it across a whole roadmap in one shot, see **Iterating over many milestones** at the bottom.

This skill is written to work with any coding agent — it never assumes a specific tool name. Wherever it says "search," "read," "edit," or "spawn a subagent," use whatever your environment's equivalent is.

Check this skill's directory for a `workflows/<your-agent>.md` adapter (e.g. `workflows/omp.md`, `workflows/claude.md`). If one matches your agent, read it — it maps the generic language below onto your environment's concrete tools, which matters most for the two optional fan-out steps. If none exists, use your own judgment to map the steps onto whatever tools you have.

## Operating rules

- Track progress through the phases below with whatever task-list mechanism your agent provides. If none is available, keep a short inline checklist of your own and update it as you go.
- Don't surface intermediate output — only the final block in the last step.
- Use your normal file-search, file-read, and file-edit capabilities for Steps 1–3. There's no required mechanism — dedicated search/read/edit tools and shell commands are equally fine; use whichever your environment provides.
- The review in Step 4 should be a **fresh, read-only pass** — ideally a separate subagent if your environment can spawn one, so it isn't anchored to the reasoning that produced the diff. If subagents aren't available, do the review yourself as a distinct pass after implementation, applying the same criteria with fresh eyes.
- **Fan-out is optional and risk-gated.** Steps 1, 3, 5, 6, 7 stay single-author and sequential — never parallelize them. Only **Step 2** (broad milestones) and **Step 4** (high-risk diffs) may fan out across multiple agents, and only when the trigger named in that step fires, and only if your environment supports running several agents concurrently. For small, local changes the plain sequential path is faster and cheaper — fanning out there is a net loss.

## Step 0 — Seed a progress checklist

Track these phases, in order:

```
Locate   → Find progress file, extract next milestone
Build    → Understand codebase, implement milestone
Review   → Run reviewer pass, apply findings
Verify   → Run build/test/lint/fmt
Finish   → Mark milestone done, commit final state
```

Mark each step done as you go.

## Step 1 — Locate the next milestone

Search for the progress file, in this preference order:

1. `plans/**/*.md` — read each, take the first uncompleted item.
2. `ROADMAP.md` at repo root.
3. `TODO.md`, `PROGRESS.md`, `MILESTONES.md`, `PLAN.md`, `docs/plan*.md`.

"Uncompleted" = an unchecked `- [ ]`, an unmarked heading, or `TODO`/`PENDING` status. Search candidates for `- \[ \]|TODO|PENDING` to jump straight to it.

Extract the **first** uncompleted milestone only (top of file): its title, acceptance criteria/sub-tasks, and any prerequisites already marked done. Implement exactly one.

If the documented milestone is ambiguous — missing acceptance criteria, underspecified behavior, conflicting requirements, or multiple materially different implementations — **stop before editing**. Ask the user targeted questions and continue the discussion until all behavior, scope, non-goals, and verification details are settled. Do not implement by inference.

If no progress file exists, tell the user and stop.

## Step 2 — Understand the codebase + validation stack

Before editing:
- Read the source files the milestone touches; search for the symbols involved.
- Determine the validation commands and **record them now** (used in Step 5), in priority order:
  1. `Justfile` / `Makefile` / `taskfile.yml` recipes named `build`, `test`, `lint`, `fmt`, `check` (find them, read the recipes).
  2. Language-native, e.g. Rust `cargo build && cargo test && cargo clippy && cargo fmt --check`; Go `go build ./... && go test ./... && golangci-lint run`; JS/TS `<pm> run build && <pm> test && <pm> run lint`; Zig `zig build test`.
  3. CI config (`.github/workflows/*`, `.gitlab-ci.yml`) for the canonical list.

**Broad or unfamiliar milestone? (optional fan-out.)** When the milestone spans several subsystems you don't already know, and your environment can run multiple subagents concurrently, dispatch a few read-only scouts in parallel instead of reading/searching serially — one per angle:

- Map the source files & symbols this milestone edits.
- Trace call sites / dispatch points for those symbols; list the invariants they rely on.
- Find existing tests & fixtures for the area and how they're run.
- Find the build/test/lint/fmt commands (Justfile/Makefile/taskfile, else CI, else language-native).

**You** merge what the scouts return and record the single validation stack yourself — don't offload that synthesis to an agent. Skip this entirely for a one-file milestone; serial reading wins there.

## Step 3 — Implement the milestone

Make the changes that satisfy the acceptance criteria, following existing style and module shape. No refactors or abstractions outside scope. Add tests only if the milestone introduces testable behavior. Do **not** mark the milestone complete yet. Leave changes unstaged so the reviewer's `git diff` sees them.

## Step 4 — Review → fix loop

Run **up to 2 rounds**:

**Get a review.** Give the reviewer (a fresh subagent if you have one, otherwise yourself in a dedicated pass) this context:

- The milestone title.
- That it's reviewing the uncommitted diff for this milestone — changes are unstaged; `git diff` shows them.
- That project conventions live in AGENTS.md / CONTRIBUTING — read and enforce them.
- To focus on correctness, safety, concurrency, API misuse, and convention violations introduced by *this* patch only.
- To read every changed file in full, trace new cross-boundary types to their dispatch points, and report each issue with enough detail to act on: title, description, priority (P0–P3), confidence, file path, and line range.
- To end with an overall verdict: correct / incorrect, explanation, confidence.

**Wait for it to finish** if it's running as a separate subagent — a thorough review can reasonably take a long time. Do other useful work while you wait if any remains; otherwise just wait. Don't poll, restart, replace, or cancel a healthy review run just because it's been running a while. Only stop it early on an explicit terminal failure, a user request, or a scope change that makes the review moot.

**Apply findings** in priority order (P0 → P3); within a priority, highest confidence first. Batch findings that land in the same function. Make only the change each finding describes. If a finding is a genuine false positive given surrounding code, keep it for the summary as "Reviewed, not applicable" — don't silently drop it.

**Loop condition:** if you applied any fix that changed logic, get one more review (round 2) on the new diff. Stop when the review comes back correct, or there's no remaining P0/P1, or after round 2 — whichever comes first. For a follow-up round, prefer continuing the same reviewer/subagent over starting fresh — it already holds context.

### High-risk mode (optional — gated on risk)

Use the default single-reviewer loop above for local, low-risk diffs. Switch to a multi-lens panel **only** when the diff trips a risk signal: it touches a **security / trust boundary**, **concurrency / async**, a **data migration or schema change**, a **broad call-graph or public-API change**, or Step 5 has **failed twice** on this milestone. For a one-file fix the panel is pure cost — don't.

If your environment supports concurrent subagents, run several review passes in parallel, each looking through one lens over the same diff:

- **canonical** — any issue at all.
- **correctness** — only correctness / data-flow / edge cases / broken invariants.
- **security** — only trust-boundary / injection / authz / secret-leak issues.
- **concurrency** — only races / lifetimes / reentrancy / ordering.
- **convention** — only project-convention & API-misuse issues (read AGENTS.md first).

Collect all findings and dedupe them yourself by (file, nearby line, same root cause) — panel members never patch the diff, only report.

Then adversarially verify what matters: every P0/P1, plus any low-confidence P2. For each, get three independent skeptics to try to refute it from concrete code evidence (each defaults to "refuted" if it can't prove the bug is real, or is unsure); a finding survives if at least 2 of 3 vote "survives." If your environment can't run subagents concurrently, do this verification serially, or skip it and apply the panel's findings directly using your own judgment.

Apply the confirmed findings exactly as the default loop describes above, record refuted findings as "Reviewed, not applicable," and run the bounded round-2 review if a logic-changing fix landed.

## Step 5 — Verify

Run the full validation stack from Step 2. Every command must pass. On failure: fix it, then re-run the **entire** stack from the top. Don't proceed until clean.

## Step 6 — Mark the milestone done

In the Step 1 file, flip `- [ ]` → `- [x]` (or set `Status: done` if the file uses that style). Edit only that single line; touch nothing else.

## Step 7 — Commit final state

Finalize the commit using this repository's `commit` skill if one is available; otherwise write a Conventional Commit message yourself following the repo's own conventions and commit directly with `git commit`. Commit only after Step 6 is complete and the working tree contains the milestone implementation, reviewer fixes, validation updates, and progress-file completion mark. If no safe agent-authored commit can be made, stop and report the exact blocker.

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

Do not print build logs, the full diff, step narration, or the reviewer's raw transcript. The user can run `git show --stat HEAD` for the committed diff.

---

## Iterating over many milestones

This skill does **one** milestone. To advance several, re-invoke it once per milestone using whatever repetition mechanism your environment provides:

- A recurring/loop mechanism if your agent has one.
- A manual repeat: run the skill, let it finish and commit, run it again.
- If your environment can run independent subagents and the milestones are genuinely independent, fan them out concurrently — one isolated subagent per milestone. Use a dependent pipeline instead (each milestone's outcome feeding the next) when milestones build on each other.
