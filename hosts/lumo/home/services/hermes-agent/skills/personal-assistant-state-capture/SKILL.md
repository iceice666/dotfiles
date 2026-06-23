---
name: personal-assistant-state-capture
description: Use when Brian asks Miku to remember something, track open loops, summarize current state, create TODOs, or decide what should become durable memory versus temporary notes.
version: 1.0.0
metadata:
  hermes:
    tags: [memory, todo, personal-assistant, state-capture, miku]
    category: personal-ops
---
# Personal Assistant State Capture

## When to Use

Use this skill when Brian asks to remember something, when a conversation produces durable decisions, or when he seems likely to lose track of open loops.

## Goal

Capture useful state without hoarding noise.

## What to Capture

Capture:

- stable preferences
- active projects and open loops
- commitments and deadlines
- decisions Brian has already made
- recurring blind spots
- shipped artifacts and evidence of progress
- reusable workflows that may become skills

Do not capture:

- passing moods
- one-off complaints
- secrets
- raw logs
- large notes
- sensitive private information unless Brian explicitly asks
- project-specific commands that belong in AGENTS.md

## Procedure

1. Summarize the candidate memory or TODO in one sentence.
2. Classify it as:
   - durable memory
   - temporary TODO
   - project note
   - parking-lot idea
   - should not be saved
3. Ask for approval if the memory is personal or sensitive.
4. Prefer concise entries.
5. For project-specific data, recommend AGENTS.md or project notes instead of user memory.

## Output Format

```md
## Captured State

Memory candidate:
- ...

TODO:
- ...

Project note:
- ...

Parking lot:
- ...

Miku recommendation:
- Save / Do not save / Ask first
```

## Pitfalls

- Do not remember every emotion.
- Do not turn memory into a diary.
- Do not store secrets.
- Do not store assumptions about Brian's feelings as fact.
