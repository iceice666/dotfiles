# Playwright CLI for agent browsing

`@playwright/cli` is pinned to 0.1.20 with its exact upstream dependencies
(including Playwright 1.64.0-alpha-2026-09-14). `package-lock.json` and the Nix
npm dependency hash fix the dependency graph. No browser download or npm install
is required on deployed hosts. Registry update checks are disabled.

`common/home-base/browser.nix` is imported only by m5pro and Framework. It installs
the CLI, the `playwright-browser` skill, and `~/.playwright/cli.config.json`.
macOS uses the Nix-managed Helium app executable; Framework uses Nix Chromium.
Both launch a separate, ephemeral profile, headless by default, with
`chromiumSandbox = true`. A browser protocol compatibility failure should be
investigated against these pinned versions, not fixed by disabling the sandbox.
Homolab and Lumo are not enabled. No remote browser service or MCP bridge is used.

## Use

After `just build` / `just switch`, restart Pi or reload its skills and invoke
`/skill:playwright-browser`. Back up existing unmanaged skill/config files before
first adoption; Home Manager deliberately does not force-overwrite them.

```sh
playwright-cli -s=my-research open https://example.com
playwright-read --session my-research
playwright-cli -s=my-research close
```

Use a unique session per task/worker. `playwright-read` extracts the current tab;
it does not navigate or close the session. Readability + Turndown produce Markdown
with final URL/title, extraction mode, total length and truncation metadata.
The default limit is 24,000 characters; `--max-chars` accepts 1–200,000. The helper
removes the CLI's echoed extraction source from output. A failed CLI call or
missing/invalid result exits nonzero. Extraction has a 60-second client deadline;
a timeout is not a promise that the daemon or its browser stopped. Always close
the task-owned session explicitly. Article extraction is heuristic: app state,
tables, shadow DOM, frames and infinite scrolling may require explicit inspection.

Configuration is a default, not an access-control boundary. The upstream CLI
merges global, project, environment and command settings. It permits powerful
`eval`/`run-code` operations; the coding agent is not sandboxed by this setup.
Do not connect personal browser profiles or expose CDP endpoints. Ask before
login, private/internal browsing or consequential actions. Text and screenshots
returned to Pi may reach its configured model provider and session history.
Runtime profiles, auth state, snapshots and downloads must not enter Git or the
Nix store. `.playwright-cli/` is ignored in this repository, but other output paths
still require care. Close only owned sessions, never another agent's browser.

## Development

```sh
cd pkgs/playwright-cli
npm ci --ignore-scripts
node --test tests/*.test.cjs
# from repository root
nix build .#playwright-cli
just fmt
just check
```

Tests exercise extraction with a local DOM fixture and parse the CLI result
protocol. Real browser smoke tests must separately validate the configured
executable, sandbox-enabled launch, dynamic content, session isolation and
cleanup on each host. Never run smoke tests against personal logged-in tabs.

Upstream: https://github.com/microsoft/playwright-cli
