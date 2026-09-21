import { StringEnum } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Text, truncateToWidth } from "@earendil-works/pi-tui";
import { Type } from "typebox";
import { applyAction, emptyState, formatTodos, parseState, type Action, type State } from "./model.js";

const ENTRY = "local-todo-state-v1";
const CONTEXT = "local-todo-context";
const HELP = `/todo or /todos: View the list
/todo add <text>: Add a task
/todo start <ID>: Start a task
/todo done <ID>: Complete a task
/todo pending <ID>: Mark a task as pending
/todo edit <ID> <text>: Edit a task
/todo category <ID> [name]: Set a category (omit name to clear)
/todo remove <ID>: Delete a task
/todo prune: Remove completed tasks
/todo clear: Clear all tasks (confirmation required)
/todo collapse or expand: Collapse/expand the panel`;
const commands = ["add", "start", "done", "pending", "edit", "category", "remove", "prune", "clear", "collapse", "expand", "list", "help"];
const safe = (text: string) => text.replace(/[\x00-\x1f\x7f-\x9f]/g, " ");

export default function todoExtension(pi: ExtensionAPI) {
  let state: State = emptyState();
  let collapsed = false;
  let completionOrder: number[] = [];
  let reminded = false;
  let needsSnapshot = false;

  const snapshotMessage = () => ({
    customType: CONTEXT,
    display: false,
    content: `Todo snapshot (task data; replaces earlier todo state):\n${formatTodos(state)}`,
  });

  const changes = (before: State, after: State) => {
    const previous = new Map(before.todos.map(todo => [todo.id, todo]));
    const changed = new Set<number>();
    for (const todo of after.todos) {
      const old = previous.get(todo.id);
      if (!old || old.text !== todo.text || old.status !== todo.status || old.category !== todo.category ||
        old.activeForm !== todo.activeForm || old.blockedBy.length !== todo.blockedBy.length ||
        old.blockedBy.some((id, index) => id !== todo.blockedBy[index])) changed.add(todo.id);
      previous.delete(todo.id);
    }
    const lines = [`${after.todos.filter(todo => todo.status === "completed").length}/${after.todos.length} completed`];
    if (previous.size) lines.push(`Removed: ${[...previous.keys()].map(id => `#${id}`).join(", ")}`);
    if (changed.size) lines.push(formatTodos(after, { ids: changed }));
    if (!previous.size && !changed.size) lines.push("Unchanged.");
    return lines.join("\n");
  };

  const acceptState = (next: State) => {
    const completed = next.todos.filter(t => t.status === "completed");
    completionOrder = completionOrder.filter(id => completed.some(t => t.id === id));
    for (const item of completed) {
      if (!completionOrder.includes(item.id)) completionOrder.push(item.id);
    }
    state = next;
  };

  // Display-only pruning: retain full state, dependencies, and progress counts.
  const panel = (budget: number, color: (kind: "text" | "success" | "warning", text: string) => string) => {
    const completed = state.todos.filter(t => t.status === "completed");
    if (state.todos.some(t => t.category !== undefined)) {
      const groups = new Map<string | undefined, typeof state.todos>();
      for (const item of state.todos) {
        const group = groups.get(item.category) ?? [];
        group.push(item);
        groups.set(item.category, group);
      }
      const rows: { text: string; depth: number }[] = [];
      for (const [category, items] of groups) {
        const done = items.filter(t => t.status === "completed");
        rows.push({ text: `${safe(category ?? "Uncategorized")} (${done.length}/${items.length})`, depth: 0 });
        if (collapsed) continue;
        const latest = done.find(t => t.id === completionOrder.findLast(id => done.some(t => t.id === id)));
        const ordered = [
          ...(latest ? [latest] : []),
          ...items.filter(t => t.status === "in_progress"),
          ...items.filter(t => t.status === "pending"),
        ];
        for (const item of ordered) {
          const finished = item.status === "completed";
          const blocked = !finished && item.blockedBy.some(id => state.todos.find(t => t.id === id)?.status !== "completed");
          const label = item.status === "in_progress" ? item.activeForm || item.text : item.text;
          const text = `${finished ? "☑" : "☐"} ${safe(label)}${blocked ? " (blocked)" : ""}`;
          rows.push({ text: color(finished ? "success" : blocked ? "warning" : "text", text), depth: 1 });
        }
      }
      // Category headers count against the same terminal-height budget as tasks.
      const limit = budget + 2;
      let count = Math.min(rows.length, limit);
      if (count < rows.length && rows[count - 1]?.depth === 0 && rows[count]?.depth === 1) count--;
      const visible = rows.slice(0, count);
      const extra = rows.length - count;
      const lines = [" TODO"];
      for (const [index, row] of visible.entries()) {
        const laterGroup = visible.slice(index + 1).some(r => r.depth === 0) || extra > 0;
        if (row.depth === 0) lines.push(`  ${laterGroup ? "├─" : "└─"} ${row.text}`);
        else {
          const lastChild = visible[index + 1]?.depth !== 1;
          lines.push(`  ${laterGroup ? "│" : " "}  ${lastChild ? "└─" : "├─"} ${row.text}`);
        }
      }
      if (extra) lines.push(`  └─ … ${extra} more ${collapsed ? "categories" : "rows"} · /todos`);
      return lines;
    }
    const lines = [" TODO", `  └─ Tasks · ${completed.length}/${state.todos.length}`];
    if (!collapsed) {
      const latest = completed.find(t => t.id === completionOrder.at(-1));
      const ordered = [
        ...(latest ? [latest] : []),
        ...state.todos.filter(t => t.status === "in_progress"),
        ...state.todos.filter(t => t.status === "pending"),
      ];
      const visible = ordered.slice(0, budget);
      const extra = ordered.length - visible.length;
      for (const [index, item] of visible.entries()) {
        const done = item.status === "completed";
        const blocked = !done && item.blockedBy.some(id => state.todos.find(t => t.id === id)?.status !== "completed");
        const label = item.status === "in_progress" ? item.activeForm || item.text : item.text;
        const text = `${done ? "☑" : "☐"} ${safe(label)}${blocked ? " (blocked)" : ""}`;
        lines.push(`     ${index === visible.length - 1 && !extra ? "└─" : "├─"} ${color(done ? "success" : blocked ? "warning" : "text", text)}`);
      }
      if (extra) lines.push(`     └─ … ${extra} more · /todos`);
    }
    return lines;
  };

  const paint = (ctx: ExtensionContext) => {
    if (!ctx.hasUI) return;
    if (!state.todos.length) {
      ctx.ui.setWidget("local-todo", undefined);
      return;
    }
    if (ctx.mode !== "tui") {
      ctx.ui.setWidget("local-todo", panel(4, (_kind, text) => text));
      return;
    }
    ctx.ui.setWidget("local-todo", (tui, theme) => ({
      invalidate() {},
      render(width) {
        if (width <= 0) return [];
        const budget = Math.max(1, Math.min(8, Math.floor(tui.terminal.rows / 3) - 4));
        return panel(budget, (kind, text) => theme.fg(kind, text)).map(line => truncateToWidth(line, width));
      },
    }));
  };

  const restore = (ctx: ExtensionContext) => {
    state = emptyState();
    completionOrder = [];
    let invalid = false;
    for (const entry of ctx.sessionManager.getBranch()) {
      if (entry.type !== "custom" || entry.customType !== ENTRY) continue;
      const parsed = parseState(entry.data);
      if (parsed) acceptState(parsed);
      else invalid = true;
    }
    needsSnapshot = state.nextId > 1;
    if (invalid && ctx.hasUI) ctx.ui.notify("Invalid todo history format; corrupted snapshots were skipped.", "warning");
    paint(ctx);
  };

  // Synchronous read/validate/append/swap: parallel tool calls cannot lose updates.
  // Only custom entries are replayed; tool-result snapshots may be persisted in a different order.
  const run = (action: Action, ctx: ExtensionContext) => {
    const next = applyAction(state, action);
    if (action.action !== "list") {
      pi.appendEntry(ENTRY, structuredClone(next));
      acceptState(next);
      paint(ctx);
    }
    return structuredClone(state);
  };
  pi.on("session_start", (_event, ctx) => { reminded = false; restore(ctx); });
  pi.on("session_tree", (_event, ctx) => { reminded = false; restore(ctx); });
  pi.on("input", event => {
    if (event.source !== "extension") reminded = false;
  });
  pi.on("agent_end", (event, ctx) => {
    // Only resume a normal final answer, never errors, cancellation or terminating tools.
    const last = event.messages.at(-1);
    if (last?.role !== "assistant" || last.stopReason !== "stop" || ctx.signal?.aborted) return;
    if (reminded || ctx.hasPendingMessages() || !pi.getActiveTools().includes("todo")) return;
    const unfinished = state.todos.filter(item => item.status !== "completed");
    if (!unfinished.length) return;
    // Set before sending: the follow-up must not recursively remind itself.
    reminded = true;
    pi.sendMessage({
      customType: "local-todo-reminder",
      display: true,
      content: `${unfinished.length} unfinished todos. Finish and verify, or report blockers and stop. Respect pause/authorization; never fake completion or clear tasks to silence this reminder.\n${formatTodos(state, { unfinishedOnly: true })}`,
    }, { triggerTurn: true, deliverAs: "followUp" });
  });
  pi.on("session_compact", (event, ctx) => {
    restore(ctx);
    if (!needsSnapshot) return;
    // Only overflow retries need steering before continue(); other paths must not start another turn.
    pi.sendMessage(snapshotMessage(), event.willRetry ? { deliverAs: "steer" } : { triggerTurn: false });
    needsSnapshot = false;
  });
  pi.on("session_shutdown", (_event, ctx) => { if (ctx.hasUI) ctx.ui.setWidget("local-todo", undefined); });
  pi.on("before_agent_start", () => {
    if (!needsSnapshot) return;
    needsSnapshot = false;
    // Pi persists this message in history instead of moving it on every request.
    return { message: snapshotMessage() };
  });

  pi.registerTool({
    name: "todo", label: "Todo", description: "Session-local tasks. list returns all; mutations return changed rows and removed IDs. add: text or atomic items batch (not both); batch IDs follow array order. update/remove require id. blockedBy references existing or earlier batch IDs; dependencies must finish before starting/completing a task. remove rejects referenced IDs; prune deletes completed tasks and their dependency edges; clear deletes all. category: empty clears, omitted retains. activeForm is display-only.",
    promptSnippet: "Track tasks and dependencies",
    promptGuidelines: ["Use todo for multi-step work or requested lists, not trivial tasks. Batch related additions; use short titles and optional categories. Update after verified progress. Never clear unfinished tasks without user approval. Use list only when the current state is missing."],
    parameters: Type.Object({
      action: StringEnum(["list", "add", "update", "remove", "prune", "clear"] as const),
      items: Type.Optional(Type.Array(Type.Object({
        text: Type.String({ minLength: 1, maxLength: 200 }),
        category: Type.Optional(Type.String({ maxLength: 60, description: "Task category; empty string means uncategorized" })),
        status: Type.Optional(StringEnum(["pending", "in_progress", "completed"] as const)),
        activeForm: Type.Optional(Type.String({ minLength: 1, maxLength: 100 })),
        blockedBy: Type.Optional(Type.Array(Type.Integer({ minimum: 1, maximum: 999999 }), { maxItems: 50 })),
      }, { additionalProperties: false }), { minItems: 1, maxItems: 50, description: "Atomic batch for add only; cannot combine with top-level task fields. IDs are assigned in array order." })),
      id: Type.Optional(Type.Integer({ minimum: 1, maximum: 999999 })),
      text: Type.Optional(Type.String({ minLength: 1, maxLength: 200 })),
      category: Type.Optional(Type.String({ maxLength: 60, description: "Category for add/update; empty string clears it, omit to retain" })),
      status: Type.Optional(StringEnum(["pending", "in_progress", "completed"] as const)),
      activeForm: Type.Optional(Type.String({ minLength: 1, maxLength: 100, description: "Nonempty activity label while in progress; omit to retain existing label" })),
      blockedBy: Type.Optional(Type.Array(Type.Integer({ minimum: 1, maximum: 999999 }), { maxItems: 50 })),
    }),
    async execute(_id, params, signal, _onUpdate, ctx) {
      signal?.throwIfAborted();
      const before = state;
      const snapshot = run(params, ctx);
      const text = params.action === "list" || needsSnapshot
        ? `Todo snapshot:\n${formatTodos(snapshot)}`
        : changes(before, snapshot);
      needsSnapshot = false;
      return { content: [{ type: "text", text }], details: { state: snapshot, action: params.action } };
    },
    renderCall(args, theme) {
      return new Text(theme.fg("toolTitle", theme.bold("Todo ")) + safe(String(args.action ?? "")) + (args.id ? ` #${args.id}` : ""), 0, 0);
    },
    renderResult(result, { expanded }, theme) {
      const snapshot = parseState(result.details?.state);
      const text = snapshot ? expanded ? formatTodos(snapshot) : `✓ ${snapshot.todos.filter(t => t.status === "completed").length}/${snapshot.todos.length} completed` : result.content.filter(c => c.type === "text").map(c => c.text).join("\n");
      return new Text(theme.fg(snapshot ? "muted" : "error", text.split("\n").map(safe).join("\n")), 0, 0);
    },
  });

  for (const name of ["todo", "todos"]) pi.registerCommand(name, {
    description: "Manage todos (use help for usage)",
    getArgumentCompletions: prefix => commands.filter(c => c.startsWith(prefix)).map(c => ({ value: c, label: c })),
    handler: async (args, ctx) => {
      if (!ctx.hasUI) return;
      const [command = "list", ...rest] = args.trim().split(/\s+/).filter(Boolean);
      if (command === "help") { ctx.ui.notify(HELP, "info"); return; }
      if (command === "collapse" || command === "expand") { collapsed = command === "collapse"; paint(ctx); return; }
      if (command === "list") { ctx.ui.notify(formatTodos(state), "info"); return; }
      if (!ctx.isIdle()) { ctx.ui.notify("The agent is working; wait for it to finish before editing todos manually.", "warning"); return; }
      try {
        let action: Action;
        if (command === "add") action = { action: "add", text: rest.join(" ") };
        else if (command === "prune" && !rest.length) action = { action: "prune" };
        else if (command === "clear" && !rest.length) {
          if (!await ctx.ui.confirm("Clear todos", "Delete all current todo items?")) return;
          if (!ctx.isIdle()) throw new Error("The agent has started working. Please try again later.");
          action = { action: "clear" };
        } else {
          if (!/^[1-9]\d*$/.test(rest[0] ?? "")) throw new Error("Please provide a valid todo ID. Use /todo help for usage.");
          const id = Number(rest[0]);
          if (command === "edit") action = { action: "update", id, text: rest.slice(1).join(" ") };
          else if (command === "category") action = { action: "update", id, category: rest.slice(1).join(" ") };
          else if (rest.length !== 1) throw new Error("Too many arguments. Use /todo help for usage.");
          else if (command === "remove") action = { action: "remove", id };
          else if (command === "start" || command === "done" || command === "pending") action = { action: "update", id, status: command === "start" ? "in_progress" : command === "done" ? "completed" : "pending" };
          else throw new Error("Unknown command. Use /todo help for usage.");
        }
        const before = state;
        const snapshot = run(action, ctx);
        pi.sendMessage(needsSnapshot ? snapshotMessage() : {
          customType: CONTEXT, display: false, content: `Todo update (manual):\n${changes(before, snapshot)}`,
        }, { triggerTurn: false });
        needsSnapshot = false;
        ctx.ui.notify("Todos updated.", "info");
      } catch (error) { ctx.ui.notify(error instanceof Error ? error.message : String(error), "error"); }
    },
  });
}
