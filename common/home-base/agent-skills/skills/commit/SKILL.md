---
name: commit
description: Group staged Agent-authored changes into logical scoped commits, write a devlog entry when the project requires one, and create commits using Conventional Commit format. Use when the user asks Codex to commit its changes, write commit messages, identify changed scopes, split unrelated changes into multiple commits, or validate changes before committing. Commit only changes authored by the Agent during the current task.
---

# Commit

## Workflow

1. Inspect repository state with `git status --short`, then review staged,
   unstaged, and untracked changes. Distinguish changes authored by the Agent
   during the current task from pre-existing user or third-party changes.
2. Commit only Agent-authored changes. Never include pre-existing changes,
   even when they are already staged. Preserve unrelated dirty work and avoid
   reverting or modifying changes the Agent did not author.
3. Identify the developer-facing or user-visible intent of each Agent-authored
   change. Group staged changes into logical scoped commits by purpose. Detect
   spec framework artifacts and associate them with their corresponding
   implementation changes.
4. Check whether the project requires a devlog entry through repository
   instructions, contributor documentation, templates, or established
   conventions. Write and stage the required devlog entry with its related
   logical commit.
5. Run the relevant validation before committing. Prefer the repository's own
   test, lint, format-check, typecheck, or CI commands. Use nearby package
   scripts, task runners, README instructions, or existing CI config to infer
   what should pass. If full validation is impractical, run the most relevant
   targeted checks and mention the limitation only outside the commit message.
6. Stage only Agent-authored files or hunks for one commit candidate at a
   time. Use path-based or hunk-based staging so unrelated or pre-existing
   changes are not mixed. Include related spec and devlog files with the
   implementation they describe.
7. Write and create each commit with a concise Conventional Commit message.
8. When reporting back to the user, return only the commit message or messages
   created, with no Markdown, raw diff, changed-file list, or extra commentary.

## Commit Splitting

Create multiple commits when changes have different intents or affected areas,
for example:

- A feature change plus unrelated test infrastructure.
- Documentation updates plus application behavior changes.
- Independent fixes in separate modules.
- Formatting-only churn mixed with semantic edits.

Keep one commit when changes are tightly coupled and describe one intent, even
if they touch several files.

## Message Format

Use this exact shape:

```text
<type>(optional-scope): <summary>

(optional-body)
```

Allowed types:

```text
feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert
```

Subject rules:

- Keep the subject under 50 characters when possible.
- Use lowercase except proper nouns.
- Use imperative mood.
- Do not end with punctuation.
- Prefer the most specific allowed type.
- Include a scope only when it clarifies the changed area.
- Do not mention file names unless essential.

Body rules:

- Omit the body for simple changes.
- Add a short body only to explain motivation, migration notes, risks, or
  behavior changes not obvious from the subject.
- Wrap body text at 72 characters.
- Use paragraphs, not a list of changed files or line-by-line diff details.

## Type Selection

Choose the type by intent:

- `feat`: add or expose user-visible behavior or capability.
- `fix`: correct broken behavior.
- `docs`: change documentation only.
- `style`: change formatting without affecting behavior.
- `refactor`: restructure code without changing behavior.
- `perf`: improve performance.
- `test`: add or change tests or test helpers.
- `build`: change dependencies, packaging, generated build inputs, or build
  tooling.
- `ci`: change CI configuration or automation.
- `chore`: maintain repository housekeeping that fits no more specific type.
- `revert`: undo an earlier commit.

## Spec Frameworks

When the repository uses a spec framework (e.g., OpenSpec, changesets, or
similar), treat spec files as part of the same logical change as the
implementation they describe.

- Detect spec artifacts (`openspec/`, `.changes/`, `docs/specs/`,
  `docs/references/`, `.agents/skills/*/SKILL.md`, etc.) during repository
  inspection.
- Stage spec changes together with their corresponding implementation files
  in the same commit. Do not split a single logical change across a
  "spec-only" and an "implementation-only" commit.
- If a spec change stands alone (e.g., creating a new spec before
  implementation, archiving completed specs, or updating reference docs
  without code changes), commit it independently using `docs`, `chore`, or
  the type that best matches the spec's intent.

## Final Output

Return only the commit message text for the commit or commits actually created.
For multiple commits, print each commit message separated by one blank line.
Do not include Markdown fences, bullets, validation logs, raw diffs, or file
lists in the final response.
