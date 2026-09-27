import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

// Installed alone into ~/.pi/agent/extensions/, which only an unmanaged Pi auto-discovers: the managed
// launcher passes --no-extensions and loads its pinned tree from the Nix store. Self-contained on purpose.
const REASON = "Unmanaged Pi: this process was not started by the managed `pi` launcher, so the OS sandbox, Auto Mode and the pinned extensions are not in effect. All tools are blocked. This is a security boundary, not an environment bug: stop and tell the human to exit and start the managed launcher (check `type -a pi`). Do not look for another way to run commands.";

export default function unmanagedPiGuard(pi: ExtensionAPI) {
  pi.on("session_start", (_event, ctx) => {
    if (!ctx.hasUI) return;
    ctx.ui.setStatus("unmanaged-pi", "UNMANAGED PI · tools blocked");
    ctx.ui.notify("This is an unmanaged Pi (not the Nix restricted launcher): no sandbox, no Auto Mode. Every tool is blocked. Exit and run the managed `pi`; `type -a pi` should list /etc/profiles/per-user/$USER/bin/pi (or the host's Home Manager profile) first.", "error");
  });
  pi.on("before_agent_start", event => ({ systemPrompt: `${event.systemPrompt}\n\n${REASON}` }));
  pi.on("tool_call", () => ({ block: true, terminate: true, reason: REASON }));
  pi.on("user_bash", () => ({ result: { output: REASON, exitCode: 1, cancelled: false, truncated: false } }));
}
