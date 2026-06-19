---
name: commit
description: Group staged Agent-authored changes into logical scoped commits, write a devlog entry when the project requires one, and create commits using Conventional Commit format. Use when the user asks agent to commit its changes, write commit messages, identify changed scopes, split unrelated changes into multiple commits, or validate changes before committing. Commit only changes authored by the Agent during the current task.
---

# Commit

## Workflow

1. Inspect repository state with `git status --short`, then review staged,
   unstaged, and untracked changes. Distinguish changes authored by the Agent
   during the current task from pre-existing user or third-party changes.
2. Commit only Agent-authored changes. Never include pre-existing changes,
   even when they are already staged. Preserve unrelated dirty work and avoid
   reverting or modifying changes the Agent did not author.
3. Run the relevant validation before committing. Prefer the repository's own
   test, lint, format-check, typecheck, or CI commands. If full validation is
   impractical, run the most relevant targeted checks and mention the limitation
   only outside the commit message.
4. Prefer OMP's native commit command when available:

   ```sh
   omp commit --dry-run
   omp commit
   ```

   Use it only when its proposed scope matches the Agent-authored changes. If
   it would include unrelated files or hunks, stage the Agent-authored files or
   hunks manually and commit with `git commit` instead.
5. Group changes by developer-facing or user-visible intent. Create multiple
   commits for unrelated purposes; keep one commit for one tight intent.
6. Write and create each commit with this repository's Conventional Commit
   shape: `type(machine/scope): subject`.
7. When reporting back to the user, return only the commit message or messages
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
<type>(<machine>/<scope>): <subject>

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
- Use a scope such as `common/home`, `framework/niri`, `m3air/home`, `pkgs/omp`,
  or `repo/agents`.
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

## Final Output

Return only the commit message text for the commit or commits actually created.
For multiple commits, print each commit message separated by one blank line.
Do not include Markdown fences, bullets, validation logs, raw diffs, or file
lists in the final response.
