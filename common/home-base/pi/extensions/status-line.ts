import { homedir } from "node:os";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

// Single-line footer. Time measures the current/last prompt, not idle time.
export default function (pi: ExtensionAPI) {
  let started: number | undefined;
  let elapsed = 0;
  let redraw = () => {};
  let refreshGit = () => {};
  let dispose = () => {};

  pi.on("agent_start", () => {
    started ??= performance.now();
    elapsed = 0;
    redraw();
  });
  pi.on("agent_settled", () => {
    if (started !== undefined) elapsed = performance.now() - started;
    started = undefined;
    refreshGit();
    redraw();
  });
  pi.on("model_select", () => redraw());
  pi.on("thinking_level_select", () => redraw());
  pi.on("tool_execution_end", () => refreshGit());
  pi.on("session_shutdown", () => dispose());

  pi.on("session_start", (_event, ctx) => {
    dispose();
    if (ctx.mode !== "tui") return;
    started = undefined;
    elapsed = 0;

    ctx.ui.setFooter((tui, theme, footerData) => {
      let closed = false;
      let pending = false;
      let branch = "";
      let status = "";
      let dirty = false;
      const abort = new AbortController();
      redraw = () => { if (!closed) tui.requestRender(); };

      const updateGit = async () => {
        if (closed || pending) return;
        pending = true;
        try {
          const result = await pi.exec("git", [
            "--no-optional-locks", "-C", ctx.cwd, "status",
            "--porcelain=v2", "--branch", "-z", "--untracked-files=normal",
          ], { timeout: 3000, signal: abort.signal });
          if (closed) return;
          branch = "";
          status = "";
          dirty = false;
          if (result.code === 0 && !result.killed) {
            let oid = "";
            let staged = 0, modified = 0, untracked = 0, conflicts = 0;
            const records = result.stdout.split("\0");
            for (let i = 0; i < records.length; i++) {
              const record = records[i];
              if (record.startsWith("# branch.head ")) branch = record.slice(14);
              else if (record.startsWith("# branch.oid ")) oid = record.slice(13, 20);
              else if (record.startsWith("? ")) untracked++;
              else if (record.startsWith("u ")) conflicts++;
              else if (record.startsWith("1 ") || record.startsWith("2 ")) {
                const xy = record.split(" ")[1];
                if (xy[0] !== ".") staged++;
                if (xy[1] !== ".") modified++;
                if (record.startsWith("2 ")) i++; // Rename's original filename.
              }
            }
            if (branch === "(detached)") branch = `@${oid}`;
            dirty = staged + modified + untracked + conflicts > 0;
            status = [staged && `+${staged}`, modified && `~${modified}`,
              untracked && `?${untracked}`, conflicts && `!${conflicts}`]
              .filter(Boolean).join(" ") || "✓";
          }
        } catch {
          if (!closed) { branch = ""; status = "git:?"; dirty = true; }
        } finally {
          pending = false;
          redraw();
        }
      };
      refreshGit = () => { void updateGit(); };
      const unsubscribe = footerData.onBranchChange(refreshGit);
      const timer = setInterval(() => { if (started !== undefined) redraw(); }, 1000);
      const gitTimer = setInterval(refreshGit, 5000);
      timer.unref();
      gitTimer.unref();
      refreshGit();
      dispose = () => {
        if (closed) return;
        closed = true;
        clearInterval(timer);
        clearInterval(gitTimer);
        abort.abort();
        unsubscribe();
      };

      const clean = (text: string) => text.replace(/[\x00-\x1f\x7f-\x9f]/g, "?");
      const fmt = (n: number) => n >= 1000 ? `${(n / 1000).toFixed(1).replace(/\.0$/, "")}k` : `${n}`;
      return {
        dispose,
        invalidate() {},
        render(width: number): string[] {
          if (width <= 0) return [""];
          const seconds = Math.floor((started === undefined ? elapsed : performance.now() - started) / 1000);
          const time = seconds < 60 ? `${seconds}s` : `${Math.floor(seconds / 60)}m${String(seconds % 60).padStart(2, "0")}s`;
          const home = homedir();
          const cwd = ctx.cwd === home ? "~" : ctx.cwd.startsWith(`${home}/`) ? `~${ctx.cwd.slice(home.length)}` : ctx.cwd;
          const usage = ctx.getContextUsage();
          const percent = usage?.percent;
          const contextText = usage && usage.tokens !== null
            ? `${fmt(usage.tokens)}/${fmt(usage.contextWindow)} ${percent == null ? "?" : percent.toFixed(0)}%`
            : "ctx ?";
          const right = theme.fg(percent != null && percent >= 90 ? "error" : percent != null && percent >= 75 ? "warning" : "muted", contextText);
          const left = [
            theme.fg(started === undefined ? "dim" : "accent", time),
            theme.fg("accent", clean(ctx.model?.id ?? "no-model")) + theme.fg("muted", `:${pi.getThinkingLevel()}`),
            theme.fg("muted", clean(cwd)) + (branch ? theme.fg("accent", `:${clean(branch)}`) : ""),
            status ? theme.fg(dirty ? "warning" : "success", status) : "",
          ].filter(Boolean).join(" ");
          const rightWidth = visibleWidth(right);
          let line: string;
          if (rightWidth >= width) line = truncateToWidth(right, width);
          else {
            const clipped = truncateToWidth(left, Math.max(0, width - rightWidth - 2));
            line = clipped + " ".repeat(Math.max(0, width - visibleWidth(clipped) - rightWidth)) + right;
          }
          // Keep other extensions' statuses visible only when they have something to report.
          const statuses = [...footerData.getExtensionStatuses().values()];
          return statuses.length ? [line, truncateToWidth(statuses.join("  ").replace(/[\r\n\t]/g, " "), width)] : [line];
        },
      };
    });
  });
}
