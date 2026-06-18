## Oh My Pi Tooling

Use Oh My Pi's native tools before shell equivalents: `read` for files, directories, archives, URLs, and internal URI schemes; `search` for content search; `find` for path lookup; `edit`/`write` for file changes; `lsp` for definitions, references, renames, diagnostics, and code actions. Do not shell out to `grep`, `rg`, `find`, `ls`, `cat`, `head`, `tail`, or `sed` when a native tool can provide the result. Outside an agent harness, prefer `rg` over `grep`.

## Codebase interop

Before broad exploration, give me a 3–5 bullet plan and list the exact files or directories you'll inspect. Use `find` and `search` to locate targets before reading. Prefer `read` summaries and line ranges over whole-file reads. Use `task` subagents for independent multi-area work, and use `lsp` for code intelligence whenever available.

## Testing & Commits

After implementing a feature, run the narrowest validation that covers the changed behavior, then run the repo-required formatter/check before finishing. For commits, prefer OMP's native `omp commit --dry-run`/`omp commit` flow when it can be constrained to agent-authored changes; never include pre-existing user work.

## Constraints / Environment

I cannot run interactive commands such as `screen` or serial consoles. When a workflow needs interactivity, prepare everything and hand off explicit commands for me to run.
