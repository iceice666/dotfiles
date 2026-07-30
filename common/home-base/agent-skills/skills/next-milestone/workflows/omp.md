---
description: Run the next-milestone skill end to end as an OMP workflow.
---

Read `skill://next-milestone` for the full behavior spec — the steps, ordering,
review-loop rules, verification, milestone-completion, commit, and final-output
requirements. Treat the skill as canonical; do not shorten, duplicate, or
reinterpret it. The mapping below only translates its agent-neutral language
("search," "read," "spawn a subagent," "track progress") onto OMP's native
tools — it adds no new behavior.

Use the following arguments only to narrow the progress file or milestone
selection. If they are empty, locate the next milestone exactly as the skill
specifies:

$@

## OMP tool mapping

**Step 0 — progress tracking.** Use the `todo` tool:

```
todo init, phases:
  Locate   → [Find progress file, Extract next milestone]
  Build    → [Understand codebase, Implement milestone]
  Review   → [Run reviewer agent, Apply findings]
  Verify   → [Run build/test/lint/fmt]
  Finish   → [Mark milestone done, Commit final state]
```

Mark each `done` as you go; the next task auto-promotes.

**Steps 1–3 — file operations.** Use the native `find`/`read`/`search`/`edit`
tools. Never shell out to `find`/`ls`/`cat`/`grep`/`rg`.

**Step 2 — optional fan-out.** Drive it from one `eval` cell:

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

**Step 4 — review.** Do **not** delegate the review to a hand-written prompt —
use the bundled **`reviewer`** agent via the `task` tool. It reads the diff,
reports issues through `report_finding`, and yields a structured verdict.

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

**Wait patiently.** A reviewer run taking an hour is normal. After dispatch, do
independent useful work if any remains; when completely blocked, use `hub wait`
with `timeoutMs: 3600000`. If that wait window expires while the reviewer is
still running, wait again. A wait timeout is not a reviewer failure. Never poll,
restart, replace, or cancel a healthy reviewer merely because it has been
running for five minutes — or for any other duration. Cancel only after an
explicit terminal failure, a user request, or a scope change that makes the
review result unnecessary.

For follow-up rounds you can `irc` the same reviewer instead of a fresh spawn —
it already holds context.

**Step 4 — high-risk panel.** Drive it from one `eval` cell:

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

**Step 7 — commit.** Use the `commit` skill as the last workflow step.

**Iterating over many milestones.**

- **`/loop`** — re-submits `/skill:next-milestone` each iteration. `loop.mode`
  (`prompt | compact | reset`) controls what happens between iterations
  (`compact`/`reset` keep context from ballooning across milestones).
- **Goal Mode** (`goal.enabled`, `goal.continuationModes`) — set a goal like
  "complete all unchecked roadmap items"; the session auto-continues between
  turns until it's met.
- **`eval` `agent()` / `pipeline()`** — drive it programmatically when
  milestones are independent:
  ```py
  # one isolated subagent per milestone, bounded fan-out
  results = parallel([lambda m=m: agent(f"Run next-milestone for: {m}") for m in milestones])
  ```
  Use `pipeline(items, *stages)` instead when each milestone depends on the
  previous one (barrier between stages).
