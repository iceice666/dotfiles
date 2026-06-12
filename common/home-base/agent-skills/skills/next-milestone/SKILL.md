---
name: next-milestone
description: Implement the next milestone in plans/ROADMAP.md/any progress file, then run a structured review subagent that audits lifecycle/contract violations, build-mode correctness, and env-var test races. Apply all flagged fixes, re-run build+test+lint+fmt, and present only the final verified diff with a bug summary.
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

Read each file in full. Then audit for every category:

## 1. Lifecycle and contract violations
- Objects or resources used before initialization completes.
- Init order dependencies: B initializes using A, but A is initialized after B.
- Resources (file handles, sockets, locks, allocations) not released on all exit paths — including early returns and error branches.
- Functions called after a resource is released (use-after-free, use-after-close).
- Null/nil/zero dereferences after a fallible call whose error is checked but the value is still used.
- Missing postcondition enforcement: a function promises to return a valid value but has a path that returns a zero/null/default silently.
- Input contract violations: a function documents or implies a non-empty slice, positive integer, or non-nil pointer but accepts the invalid input without erroring.

## 2. Build-mode correctness
- Optimization mode mismatch: production code built with debug/safe mode (e.g. Zig `Debug` or `ReleaseSafe` where `ReleaseFast` is required; Rust `dev` profile where `release` is required; C `-O0` where `-O2`/`-O3` is required).
- Assert-only or debug-only code paths that are accidentally included in release builds.
- Compile-time flags or feature gates that disable safety checks unintentionally in non-debug builds.
- Build scripts or Makefiles that hardcode a development-only mode.

## 3. Env-var test races
- Tests that call `os.Setenv`, `std::env::set_var`, `os.environ[...]`, or equivalent without per-test isolation (e.g. `t.Setenv` in Go, `temp_env::with_var` in Rust).
- Parallel tests (e.g. `t.Parallel()` in Go, `#[tokio::test]` with default multi-thread) that mutate or read the same env var.
- Tests that read an env var and assume its value without resetting it between runs (order-dependent test suite).
- TOCTOU on env vars: check then use with a possible mutation in between.

## 4. Slot and argument ordering bugs
- Constructor or function call arguments passed in wrong positional order (e.g. width/height swapped, src/dst swapped).
- Struct literal fields initialized in a different order than the struct definition, where order matters (e.g. C bitfields, packed structs, protocol frames).
- Protocol or interface method implementation that fulfills the wrong slot (method B implements what method A should, or vice versa).

For each finding, produce one entry:

---
FINDING #N
Category: <Lifecycle | BuildMode | EnvRace | SlotOrder>
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
      "category": "Lifecycle",
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
| 1 | Lifecycle | High | src/foo.rs:42 | ... | ... |
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
