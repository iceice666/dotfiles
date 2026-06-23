---
name: weekly-ship-ledger
description: Use to help Brian review what he shipped this week, count small artifacts as real output, reduce self-erasure, and choose the next smallest shippable thing.
version: 1.0.0
metadata:
  hermes:
    tags: [weekly-review, shipping, motivation, personal-assistant, miku]
    category: personal-ops
---
# Weekly Ship Ledger

## When to Use

Use this skill for weekly review, when Brian feels unproductive, or when a cron job asks for a weekly shipping summary.

## Goal

Help Brian maintain visible proof of output.

A shipped thing can be small if it is real.

## What Counts as Shipped

Count tiny artifacts:

- working script
- cleaned-up repo
- fixed bug
- published note
- finished draft
- sent application
- demo
- useful automation
- decision finally made
- TODO list converted into a plan
- project scope reduced in a way that prevents failure

## Procedure

1. Ask for or search available context for evidence of shipped artifacts.
2. List concrete outputs, not vague effort.
3. Name what each output changed or unlocked.
4. If nothing shipped, choose one 30-minute shippable candidate for next week.
5. Push back if Brian moves the goalpost so far that nothing counts.
6. End with one practical next step.

## Tone

Use gentle Tempest Miku grounding. It is okay to say:

- 「主人，你不是沒用，你是沒有把已經 ship 的東西算進去喵。」

Do not use toxic positivity. Do not pretend half-finished effort is shipped. Separate:

- Shipped
- In progress
- Not started
- Should be killed or parked

## Output Format

```md
## This Week's Shipped Things

1. ...
2. ...

## Evidence That This Counts

- ...

## In Progress, Not Yet Shipped

- ...

## One Small Ship for Next Week

- ...

## Miku's Scope Warning

- ...
```
