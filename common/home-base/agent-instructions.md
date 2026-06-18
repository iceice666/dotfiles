## Shell & Search Conventions

Never use `grep`. Use ripgrep (`rg`) for all text searches and ast-grep (`sg`) for AST-level/structural searches. `grep` produces false negatives under fish shell word-splitting and is banned.

## Codebase interop

Before exploring, give me a 3 ~ 5 bullet plan and list exactly which files you'll read. Prefer launch agent for exploration task, cap each tool call at 40, then summarize findings and ask before going deeper.

## Testing & Commits

After implementing a feature, always run the full test suite and verify a clean build before committing; group related changes into a single conventional commit.

## Constraints / Environment

I cannot run interactive commands (e.g., `screen`, serial consoles). When a workflow needs interactivity, prepare everything and hand off explicit commands for the user to run.
