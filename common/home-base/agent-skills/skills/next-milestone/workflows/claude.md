---
description: Run the next-milestone skill end to end using Claude Code's native tools.
---

Read `SKILL.md` in this same skill directory for the full behavior spec — the
steps, ordering, review-loop rules, verification, milestone-completion,
commit, and final-output requirements. Treat it as canonical; do not shorten,
duplicate, or reinterpret it. The mapping below only translates its
agent-neutral language ("track progress," "spawn a subagent," "fan out") onto
Claude Code's native tools — it adds no new behavior.

## Claude Code tool mapping

**Step 0 — progress tracking.** `TaskCreate` one task per item below, then
`TaskUpdate` to `in_progress`/`completed` as you go:

```
Locate   → Find progress file, Extract next milestone
Build    → Understand codebase, Implement milestone
Review   → Run reviewer pass, Apply findings
Verify   → Run build/test/lint/fmt
Finish   → Mark milestone done, Commit final state
```

**Steps 1–3 — file operations.** Use `Glob`/`Grep`/`Read`/`Edit` (or `Bash`
when nothing else fits) exactly as you normally would; nothing here changes
your usual tool choice.

**Step 2 — optional fan-out.** Only worth it when the milestone spans several
unfamiliar subsystems. This is a handful of independent read-only lookups,
not deterministic orchestration, so the plain `Agent` tool is enough — send
all scout dispatches in one message so they run concurrently:

```
Agent(description: "Map milestone files & symbols", subagent_type: "Explore",
      prompt: "Map the source files & symbols this milestone edits: <criteria>.")
Agent(description: "Trace call sites", subagent_type: "Explore",
      prompt: "Trace call sites / dispatch points for <symbols>; list the invariants they rely on.")
Agent(description: "Find existing tests", subagent_type: "Explore",
      prompt: "Find existing tests & fixtures for <area> and how they are run.")
Agent(description: "Find validation commands", subagent_type: "Explore",
      prompt: "Find the build/test/lint/fmt commands (Justfile/Makefile/taskfile, else CI, else language-native).")
```

**You** merge what the scouts return and record the single validation stack yourself.

**Step 4 — review.** Spawn a fresh subagent with the `Agent` tool so the
review isn't anchored to the reasoning that produced the diff. Run it in the
foreground (`run_in_background: false`) since you need the verdict before
applying fixes:

```
Agent(
  description: "Review milestone diff",
  subagent_type: "general-purpose",   # or a dedicated review-focused type if your setup has one
  run_in_background: false,
  prompt: "Milestone: <title>. Review the uncommitted diff for this milestone
    (git diff shows it; changes are unstaged). Project conventions live in
    AGENTS.md / CONTRIBUTING — read and enforce them. Focus on correctness,
    safety, concurrency, API misuse, and convention violations introduced by
    THIS patch only. Read every changed file in full and trace new
    cross-boundary types to their dispatch points. Report each issue with:
    title, description, priority (P0-P3), confidence, file path, line range.
    End with an overall verdict: correct/incorrect, explanation, confidence."
)
```

For round 2, resume the same reviewer with `SendMessage` (`to:` its agent
name/id) instead of spawning fresh — it already holds context.

**Step 4 — high-risk panel.** This is genuine multi-agent orchestration
(parallel lenses, then adversarial verification), and the skill itself is
your explicit opt-in to use the `Workflow` tool for it:

```js
export const meta = {
  name: 'next-milestone-review-panel',
  description: 'Multi-lens review + adversarial verification for a high-risk milestone diff',
  phases: [{ title: 'Review' }, { title: 'Verify' }],
}

const VERDICT = {
  type: 'object', additionalProperties: false,
  required: ['overall_correctness', 'explanation', 'confidence', 'findings'],
  properties: {
    overall_correctness: { enum: ['correct', 'incorrect'] },
    explanation: { type: 'string' },
    confidence: { type: 'number' },
    findings: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        required: ['title', 'body', 'priority', 'confidence', 'file_path', 'line_start', 'line_end'],
        properties: {
          title: { type: 'string' }, body: { type: 'string' },
          priority: { enum: ['P0', 'P1', 'P2', 'P3'] }, confidence: { type: 'number' },
          file_path: { type: 'string' }, line_start: { type: 'number' }, line_end: { type: 'number' },
        },
      },
    },
  },
}

const DIFF = "the uncommitted diff for milestone <title> (run `git diff`)"
const LENSES = [
  ['canonical',   'Review THIS patch for any issue. ' + DIFF],
  ['correctness', 'ONLY correctness / data-flow / edge cases / broken invariants. ' + DIFF],
  ['security',    'ONLY trust-boundary / injection / authz / secret-leak issues. ' + DIFF],
  ['concurrency', 'ONLY races / lifetimes / reentrancy / ordering. ' + DIFF],
  ['convention',  'ONLY project-convention & API-misuse issues (read AGENTS.md first). ' + DIFF],
]
const reviews = await parallel(LENSES.map(([key, prompt]) => () =>
  agent(prompt, { label: `rev:${key}`, phase: 'Review', schema: VERDICT })))
const findings = reviews.filter(Boolean).flatMap(r => r.findings)
// >>> dedupe `findings` here by (file_path, nearby line, same root cause) <<<

const REF = {
  type: 'object', additionalProperties: false, required: ['verdict', 'rationale'],
  properties: { verdict: { enum: ['survives', 'refuted'] }, rationale: { type: 'string' } },
}
const hot = f => f.priority === 'P0' || f.priority === 'P1' || (f.priority === 'P2' && f.confidence < 0.6)
const survives = async f => {
  const votes = await parallel(Array.from({ length: 3 }, () => () =>
    agent(`Try to REFUTE this finding from concrete code evidence. Return 'refuted' if you cannot ` +
      `prove it is a real bug, or are unsure.\nFinding: ${f.title} @ ${f.file_path}:${f.line_start}\n${f.body}`,
      { phase: 'Verify', schema: REF })))
  return votes.filter(Boolean).filter(v => v.verdict === 'survives').length >= 2
}

const confirmed = []
for (const f of findings) if (!hot(f) || await survives(f)) confirmed.push(f)
return { confirmed }
```

Apply `confirmed` exactly as the default loop describes, record refuted
findings as "Reviewed, not applicable," and run the bounded round-2 review
(plain `Agent` call, not `Workflow`) if a logic-changing fix landed.

**Step 7 — commit.** Invoke the `commit` skill.

**Iterating over many milestones.**

- **`loop` skill** — `/loop next-milestone` re-submits this skill each
  iteration; omit the interval to let the model self-pace between milestones.
- **`Workflow` tool** — drive it programmatically when milestones are
  independent:
  ```js
  const results = await parallel(milestones.map(m => () => agent(`Run next-milestone for: ${m}`)))
  ```
  Use `pipeline(items, ...stages)` instead when each milestone depends on the
  previous one (no barrier between stages, unlike `parallel`).
