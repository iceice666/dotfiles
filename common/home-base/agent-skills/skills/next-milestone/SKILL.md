---
name: next-milestone
description: Implement the next milestone in plans/ROADMAP.md/any progress file, then run a structured review subagent that audits for bugs and project-convention violations. Apply all flagged fixes, re-run build+test+lint+fmt, and present only the final verified diff with a bug summary.
trigger: /next-milestone
---

# /next-milestone

Implement the next uncompleted milestone, then audit, fix, verify, and present a clean final diff.

## What You Must Do

Follow these steps in order. Do not skip steps. Do not present intermediate output to the user — only the final diff and bug summary at the end.

---

### Step 1 — Locate the next milestone

Search for milestone/progress files in this order of preference:

1. `plans/` directory: read all `.md` files, find the first uncompleted item (unchecked `- [ ]`, unmarked heading, or `TODO`/`PENDING` status).
2. `ROADMAP.md` at the repo root.
3. Any file matching `TODO.md`, `PROGRESS.md`, `MILESTONES.md`, `PLAN.md`, or `docs/plan*.md`.

Read the file. Extract:
- The exact milestone title/description.
- Any acceptance criteria or sub-tasks listed under it.
- Dependencies or prerequisites already marked done.

If no milestone file is found, tell the user and stop.

If multiple uncompleted milestones exist, implement only the **first** one (top of file, earliest section). Do not implement multiple at once.

---

### Step 2 — Understand the codebase shape

Before writing any code:
- Run `rg --files | head -60` to get a sense of the file tree.
- Read relevant source files the milestone will touch.
- Check existing tests, build scripts, and CI config to know what commands validate the project.

Infer the validation command stack from this priority order:
1. `Justfile` / `Makefile` / `taskfile.yml` recipes named `build`, `test`, `lint`, `fmt`, or `check`.
2. Language-native: `cargo build && cargo test && cargo clippy && cargo fmt --check` for Rust; `zig build test` for Zig; `go build ./... && go test ./... && golangci-lint run` for Go; `npm run build && npm test && npm run lint` for JS/TS; etc.
3. CI config (`.github/workflows/`, `.gitlab-ci.yml`) for the canonical command list.

Record the exact commands you will use in Step 5.

---

### Step 3 — Implement the milestone

Make all necessary code changes to satisfy the milestone acceptance criteria.

Rules:
- Follow the existing code style, naming, and module shape exactly.
- Do not refactor code outside the milestone scope.
- Do not introduce abstractions the milestone doesn't require.
- Add tests if the milestone requires new behavior that is testable.
- Do not mark the milestone as complete in the progress file yet — that happens last.

---

### Step 4 — Spawn the review subagent

After implementation, spawn a **single** review subagent using the Agent tool. Do not proceed to Step 5 until it returns.

The subagent receives this prompt (substitute `CHANGED_FILES` with the list of files you modified):

```
You are a strict code auditor. Review the following changed files for the bug categories below.
For each finding, output a structured entry. At the end, output a machine-readable JSON block.

Changed files:
CHANGED_FILES

First, read the project's `AGENTS.md` and any contributing or coding-guidelines files. Extract the project's required conventions, forbidden patterns, naming rules, and test standards — these become the basis for category 5 below.

Use native harness tools for file lookup and content search. Do not use shell `grep`, `rg`, `find`, or shell glob expansion when `search`/`find` tools are available.

Read each file in full. Then audit for every category:

## 1. Logic and correctness
- Off-by-one errors in loops, slices, indices, or range checks.
- Wrong boolean condition (e.g. `<` vs `<=`, `&&` vs `||`, negated predicate).
- Incorrect algorithm or formula — produces wrong output on valid inputs.
- Missing case in a switch/match/if-chain that silently falls through to a default.
- Early return or break that skips required side-effects (state update, cleanup, notification).
- Silent data truncation or precision loss (integer overflow, float rounding, string cut).

## 2. Safety and resource management
- Resources (file handles, sockets, locks, memory, DB connections) not released on all exit paths — including early returns and error branches.
- Use of an object or handle after it has been released, closed, or moved.
- Null/nil/zero dereference after a fallible call whose error is checked but whose value is still used.
- Missing postcondition: a function promises a valid return value but has a path that silently returns zero/null/empty.
- Input not validated at a trust boundary: function implies a non-empty slice, positive integer, or non-nil pointer but accepts the invalid input without erroring.
- Initialization order hazard: component B uses component A, but A is constructed after B.

## 3. Concurrency and shared state
- Shared mutable state (globals, caches, singletons, env vars) mutated in tests without per-test isolation or cleanup — causes order-dependent or parallel-test failures.
- Data races: two threads/goroutines read and write the same location with no synchronization.
- Deadlock potential: locks acquired in inconsistent order across call sites.
- TOCTOU: a check is separated from its use by a window where the state can change.
- Async/await or promise mis-chaining that drops errors or resolves in the wrong order.

## 4. Interface and API misuse
- Arguments passed in wrong positional order (e.g. width/height swapped, src/dst swapped, key/value swapped).
- Method implements the wrong interface slot (method B fulfills what method A should, or vice versa).
- Caller ignores a required return value or error.
- Configuration or build flags applied at the wrong scope (dev-only flag leaking into release; release optimization missing in a production path).
- Dependency injected into the wrong consumer, or two wired-up components with swapped roles.

## 5. Project-convention violations
- Any pattern explicitly forbidden by the project's `AGENTS.md` or contributor guidelines.
- Naming convention violations: function, type, module, or test names that contradict the project's stated rules.
- Missing required metadata: doc comments, spec references, formal-backing links, or file-level annotations the project mandates.
- Test names that don't follow the project's stated convention.

For each finding, produce one entry:

---
FINDING #N
Category: <Logic | Safety | Concurrency | Interface | Convention>
Severity: <Critical | High | Medium | Low>
File: <path>:<line>
Description: <one sentence — what is wrong>
Fix: <one sentence — exact change needed>
---

After all findings, output this JSON block (even if empty):

```json
{
  "findings": [
    {
      "id": 1,
      "category": "Logic",
      "severity": "High",
      "file": "src/foo.rs",
      "line": 42,
      "description": "...",
      "fix": "..."
    }
  ]
}
```

If there are zero findings, output `{"findings": []}`.
Be adversarial. Default to flagging if uncertain. Do not omit low-severity findings.
```

---

### Step 5 — Parse findings and apply fixes

Read the subagent's output. Parse the JSON findings block.

For each finding in order of severity (Critical → High → Medium → Low):
- Apply the fix described.
- If two findings are in the same function, apply them together.
- Do not introduce new logic beyond what the fix requires.

If a finding is a false positive (the described condition cannot actually occur given the surrounding code), note it in the bug summary as "Reviewed, not applicable" — do not silently discard it.

---

### Step 6 — Re-run build, test, lint, and fmt

Run the full validation command stack identified in Step 2. Every command must pass.

If a command fails:
- Fix the failure.
- Re-run the full stack from the beginning of Step 6.
- Do not proceed until all commands pass cleanly.

---

### Step 7 — Mark the milestone complete

In the progress file found in Step 1, mark the milestone as done:
- Change `- [ ]` to `- [x]`.
- Add a `Status: done` or similar annotation if the file uses that style.
- Do not edit anything else in the file.

---

### Step 8 — Present the final output

Output **only** this structure — nothing else:

```
## Milestone: <title>

### Changes
<git diff --stat output for the implementation>

### Bugs caught and fixed by review

| # | Category | Severity | Location | Bug | Fix applied |
|---|----------|----------|----------|-----|-------------|
| 1 | Safety | High | src/foo.rs:42 | ... | ... |
...

(If no bugs were found: "Review found no issues.")

### Verified
Build: ✓  Tests: ✓  Lint: ✓  Fmt: ✓
```

Do not include:
- Intermediate build logs.
- The full diff (only `--stat`).
- Any narration of what you did step by step.
- The subagent's raw output.

The user can run `git diff HEAD` themselves for the full diff.
