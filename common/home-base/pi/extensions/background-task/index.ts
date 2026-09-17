import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { truncateTail } from "@earendil-works/pi-coding-agent";
import { StringEnum } from "@earendil-works/pi-ai";
import { Type } from "typebox";
import { resolve } from "node:path";
import { stripVTControlCharacters } from "node:util";
import { TaskManager, type TaskInfo, type WaitResult } from "./manager";
import { BackgroundPanel } from "./panel";

const HELP = `/bg or /bg panel — Live task panel (Ctrl+Shift+B)
/bg start <shell command> — Run in the background
/bg list — List tasks
/bg output <id> [lines] — Show recent output (default: 200 lines)
/bg stop <id> — Stop the process group
/bg stop-all — Stop all tasks
Esc does not stop background tasks; exiting, switching sessions, or /reload does.
Tasks run with the current user's permissions, not in a sandbox.`;
const clean = (text: string) => stripVTControlCharacters(text).replace(/[\x00-\x08\x0b-\x1f\x7f]/g, "");
const summary = (task: TaskInfo) => `${task.id} · ${task.status}${task.exitCode != null ? ` (exit ${task.exitCode})` : ""} · ${clean(task.command).replace(/\s+/g, " ").slice(0, 180)}`;

export default function (pi: ExtensionAPI) {
  let ctx: ExtensionContext | undefined;
  let closed = false;
  let panel: BackgroundPanel | undefined;
  let panelOpening = false;
  const refresh = () => {
    if (!ctx?.hasUI || closed) return;
    const running = manager.list().filter(t => t.status === "running" || t.status === "stopping");
    ctx.ui.setStatus("background-task", running.length ? `BG ${running.length}` : undefined);
  };
  const manager = new TaskManager(task => {
    if (closed) return;
    refresh();
    if (ctx?.hasUI) ctx.ui.notify(`Background task: ${summary(task)}`, task.status === "failed" || task.status === "timed_out" ? "warning" : "info");
    // Queue context without starting a paid model turn or interrupting the user.
    pi.sendMessage({ customType: "background-task-finished", content: `Background shell task finished: ${summary(task)}\nLog: ${task.logPath}\nUse background_task output to inspect results.`, display: true, details: task }, { deliverAs: "nextTurn" });
  });
  const requireOpen = () => { if (closed) throw new Error("Background task runtime has shut down."); };
  const output = (id: string, lines = 200) => {
    if (!Number.isInteger(lines) || lines < 1 || lines > 2000) throw new Error("lines must be an integer from 1 to 2000.");
    const task = manager.get(id);
    const raw = clean(manager.output(id, lines));
    const markers = raw.split("\n").filter(line => /^\[(Output|Log) truncated:/.test(line)).join("\n");
    const tail = truncateTail(raw, { maxLines: lines, maxBytes: 48 * 1024 });
    return `${summary(task)}\ncwd: ${task.cwd}\nLog (capped at 10 MiB): ${task.logPath}\n${tail.truncated ? `[Display truncated]\n${markers ? `${markers}\n` : ""}` : ""}${tail.content}`;
  };
  pi.on("session_start", (_event, context) => { ctx = context; refresh(); });
  pi.on("session_shutdown", async () => {
    closed = true;
    panel?.close();
    if (ctx?.hasUI) ctx.ui.setStatus("background-task", undefined);
    await manager.shutdown();
    ctx = undefined;
  });
  pi.registerTool({
    name: "background_task",
    label: "Background Task",
    description: "Start/list/output/wait/stop background Bash jobs. Start returns immediately. Wait blocks until a job finishes or its wait timeout expires (default 60 seconds); timeout or Esc cancels only the wait, not the job. Session-local; Esc does not stop jobs, shutdown/reload/session switch does. Maximum 8 active jobs. Output is a bounded tail (up to 2000 lines/48 KiB); log files cap at 10 MiB. No stdin/PTY. Not sandboxed; same permissions as Bash. Completion is queued for the next user turn, not an automatic agent wakeup.",
    promptSnippet: "Run and manage background Shell commands without blocking the conversation",
    promptGuidelines: ["Use background_task for long-running tests, builds or development servers. Do not busy-poll; continue other work, use background_task wait when completion is needed, or let the user know the task is running. Use background_task stop explicitly when finished with a server. Never use background_task to bypass command approval or sandbox restrictions."],
    parameters: Type.Object({
      action: StringEnum(["start", "list", "output", "wait", "stop"] as const),
      command: Type.Optional(Type.String({ minLength: 1, maxLength: 16000 })),
      cwd: Type.Optional(Type.String({ description: "Working directory, relative to session cwd or absolute" })),
      timeout: Type.Optional(Type.Number({ exclusiveMinimum: 0, maximum: 86400, description: "Seconds: start job deadline (default unlimited), or wait deadline (default 60); wait timeout does not stop the job" })),
      id: Type.Optional(Type.String()),
      lines: Type.Optional(Type.Integer({ minimum: 1, maximum: 2000 })),
    }),
    async execute(_id, params, signal, _update, context) {
      signal?.throwIfAborted();
      requireOpen();
      ctx = context;
      let text: string;
      let wait: WaitResult | undefined;
      if (params.action === "start") {
        if (!params.command?.trim()) throw new Error("command is required for start.");
        const task = manager.start({ command: params.command, cwd: resolve(context.cwd, (params.cwd ?? ".").replace(/^@/, "")), timeout: params.timeout });
        text = `${summary(task)}\nLog: ${task.logPath}\nStarted in background; this is not a completion result.`;
      } else if (params.action === "list") {
        text = manager.list().map(summary).join("\n") || "No background tasks.";
      } else {
        if (!params.id) throw new Error("id is required.");
        if (params.action === "wait") {
          if (params.lines !== undefined && (!Number.isInteger(params.lines) || params.lines < 1 || params.lines > 2000)) throw new Error("lines must be an integer from 1 to 2000.");
          wait = await manager.wait(params.id, { timeout: params.timeout, signal });
          const notice = wait.outcome === "finished" ? "Wait finished; check task status and exit code."
            : wait.outcome === "timed_out" ? "Wait timed out; the job was not stopped."
            : "Wait cancelled; the job was not stopped.";
          text = `${notice}\n${output(params.id, params.lines)}`;
        } else text = params.action === "stop" ? summary(await manager.stop(params.id)) : output(params.id, params.lines);
      }
      refresh();
      return { content: [{ type: "text", text }], details: { ...(wait ? { wait: { outcome: wait.outcome, task: { ...wait.task, command: wait.task.command.slice(0, 180) } } } : {}), tasks: manager.list().map(task => ({ ...task, command: task.command.slice(0, 180) })) } };
    },
  });
  const showPanel = async (context: ExtensionContext) => {
    requireOpen();
    if (context.mode !== "tui") {
      if (context.hasUI) context.ui.notify("The live panel requires TUI mode. Use /bg list or /bg output <id>.", "warning");
      return;
    }
    if (panel) { panel.close(); return; }
    if (panelOpening) return;
    panelOpening = true;
    try {
      await context.ui.custom<void>((tui, theme, kb, done) => {
        panel = new BackgroundPanel(manager, theme,
          () => Math.max(1, Math.floor(tui.terminal.rows * 0.85)),
          () => tui.requestRender(), () => done(undefined),
          data => kb.matches(data, "tui.select.cancel"));
        return panel;
      }, { overlay: true, overlayOptions: { width: "95%", maxHeight: "85%", anchor: "center" } });
    } finally {
      panel?.dispose();
      panel = undefined;
      panelOpening = false;
    }
  };
  pi.registerShortcut("ctrl+shift+b", {
    description: "Toggle live background task panel",
    handler: showPanel,
  });
  pi.registerCommand("bg", {
    description: "Live background task panel / start / list / output / stop / stop-all",
    getArgumentCompletions: prefix => ["panel", "start", "list", "output", "stop", "stop-all", "help"].filter(s => s.startsWith(prefix)).map(s => ({ value: s, label: s })),
    handler: async (args, context) => {
      ctx = context;
      try {
        requireOpen();
        const match = args.trim().match(/^(\S+)(?:\s+([\s\S]*))?$/);
        const action = match?.[1] ?? (context.mode === "tui" ? "panel" : "list");
        if (action === "panel") { await showPanel(context); return; }
        const rest = match?.[2] ?? "";
        let text: string;
        if (action === "start") {
          const task = manager.start({ command: rest, cwd: context.cwd });
          text = `${summary(task)}\nLog: ${task.logPath}`;
        } else if (action === "list") text = manager.list().map(summary).join("\n") || "No background tasks.";
        else if (action === "output") {
          const [id, lines, extra] = rest.split(/\s+/);
          if (!id || extra) throw new Error("Usage: /bg output <id> [lines]");
          text = output(id, lines === undefined ? 200 : Number(lines));
        } else if (action === "stop") text = summary(await manager.stop(rest));
        else if (action === "stop-all") {
          await Promise.all(manager.list().filter(t => t.status === "running" || t.status === "stopping").map(t => manager.stop(t.id)));
          text = "All background tasks stopped.";
        } else text = HELP;
        refresh();
        // Explicit command output is recorded; no extra LLM turn is triggered.
        pi.sendMessage({ customType: "background-task-command", content: text, display: true });
      } catch (error) {
        if (context.hasUI) context.ui.notify(String(error), "error");
        else throw error;
      }
    },
  });
}
