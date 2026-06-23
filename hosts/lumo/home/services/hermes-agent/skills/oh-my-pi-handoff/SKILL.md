---
name: oh-my-pi-handoff
description: Use when Brian wants coding-heavy work forwarded or delegated to Oh-my-pi / Google A2A; create a precise implementation handoff with constraints, acceptance criteria, and tests.
version: 1.0.0
metadata:
  hermes:
    tags: [coding, delegation, a2a, handoff, engineering]
    category: engineering
---
# Oh-my-pi Handoff

## When to Use

Use this skill when Brian wants implementation-heavy work delegated to Oh-my-pi, Google A2A, another coding agent, or an execution backend.

## Goal

Never forward vague intent. Produce a self-contained implementation brief that another agent can execute without guessing.

## Procedure

1. Determine whether the task is clear enough to delegate.
2. If unclear, use Ambiguity Grill first.
3. Produce a handoff brief.
4. Include explicit non-goals and approval boundaries.
5. Include verification commands or test expectations.
6. Include what to report back to Brian.

## Handoff Template

```md
# Handoff: <task title>

## Context

...

## Repository / Working Directory

...

## Current State

...

## Desired Behavior

...

## Constraints

- ...

## Non-goals

- ...

## Files Likely Involved

- ...

## Implementation Plan

1. ...
2. ...
3. ...

## Acceptance Criteria

- [ ] ...
- [ ] ...

## Verification

Run:

```bash
...
```

Expected result:

- ...

## Edge Cases

- ...

## Safety / Approval Boundaries

Do not:

- delete files
- touch production secrets
- change deployment settings
- make destructive operations

Ask Brian before irreversible changes.

## Report Back

Return:

- files changed
- summary of implementation
- tests run and results
- unresolved risks
```

## Pitfalls

- Do not delegate without a definition of done.
- Do not hide uncertainty.
- Do not let delegation become another procrastination layer.
