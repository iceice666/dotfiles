import { realpath } from "node:fs/promises";
import { StringEnum } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Text, truncateToWidth } from "@earendil-works/pi-tui";
import { Type } from "typebox";
import { applyAction, emptyState, formatTodos, parseState, type Action, type State } from "./model.js";
import { approveAction } from "../auto-mode/index.js";
import { VerificationGate, invalidateGated, formatEvidence } from "./verification.js";

const checksSchema = () => Type.Array(Type.Object({
  name: Type.String({ minLength: 1, maxLength: 100 }),
  command: Type.String({ minLength: 1, maxLength: 4000 }),
}, { additionalProperties: false }), { minItems: 1, maxItems: 10, description: "Immutable completion checks; requires explicit human approval on creation" });

const ENTRY = "local-todo-state-v1";
const CONTEXT = "local-todo-context";
const HELP = `/todo or /todos: View the list
/todo add <text>: Add a task
/todo start <ID>: Start a task
/todo done <ID>: Complete a task
/todo verify <ID>: Run the task's approved checks (120 seconds per check)
/todo pending <ID>: Mark a task as pending
/todo edit <ID> <text>: Edit a task
/todo category <ID> [name]: Set a category (omit name to clear)
/todo remove <ID>: Delete a task
/todo prune: Remove completed tasks
/todo clear: Clear all tasks (confirmation required)
/todo collapse or expand: Collapse/expand the panel`;
const commands = ["verify", "add", "start", "done", "pending", "edit", "category", "remove", "prune", "clear", "collapse", "expand", "list", "help"];
const safe = (text: string) => text.replace(/[\x00-\x1f\x7f-\x9f]/g, " ");

export function registerTodo(pi: ExtensionAPI, dependencies: { gate?: VerificationGate; approve?: typeof approveAction } = {}) {
  let state: State = emptyState();
  let collapsed = false;
  let completionOrder: number[] = [];
  let reminded = false;
  let needsSnapshot = false;
  const gate = dependencies.gate ?? new VerificationGate();
  const approve = dependencies.approve ?? approveAction;
  let lifecycle = new AbortController();
  let queue: Promise<unknown> = Promise.resolve();
  const serial = <T>(operation: () => Promise<T> | T): Promise<T> => {
    const result = queue.then(operation);
    queue = result.catch(() => {});
    return result;
  };

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
    gate.reset();
    state = emptyState();
    completionOrder = [];
    let invalid = false;
    for (const entry of ctx.sessionManager.getBranch()) {
      if (entry.type !== "custom" || entry.customType !== ENTRY) continue;
      const parsed = parseState(entry.data);
      if (parsed) acceptState(parsed);
      else invalid = true;
    }
    acceptState(invalidateGated(state, new Set()));
    needsSnapshot = state.nextId > 1;
    if (invalid && ctx.hasUI) ctx.ui.notify("Invalid todo history format; corrupted snapshots were skipped.", "warning");
    paint(ctx);
  };

  const persist = (next: State, ctx: ExtensionContext) => {
    pi.appendEntry(ENTRY, structuredClone(next));
    acceptState(next);
    paint(ctx);
  };
  const revalidate = async (ctx: ExtensionContext, signal?: AbortSignal) => {
    signal?.throwIfAborted();
    const valid = await gate.current(state, ctx.cwd, signal);
    signal?.throwIfAborted();
    const next = invalidateGated(state, valid);
    if (JSON.stringify(next) !== JSON.stringify(state)) persist(next, ctx);
    return valid;
  };
  // All async approvals, verification, lifecycle restore and mutations share one queue.
  const run = async (action: Action, ctx: ExtensionContext, signal?: AbortSignal, update?: (text: string) => void) => {
    signal?.throwIfAborted();
    const sessionSignal = lifecycle.signal;
    const valid = await revalidate(ctx, signal);
    signal?.throwIfAborted();
    if (action.action === "verify") {
      if (Object.keys(action).some(key => !["action", "id"].includes(key))) throw new Error("verify accepts only action and id");
      const todo = state.todos.find(todo => todo.id === action.id);
      if (!todo) throw new Error("Task ID not found");
      if (todo.blockedBy.some(id => state.todos.find(item => item.id === id)?.status !== "completed")) throw new Error("Finish dependencies before verification");
      const evidence = await gate.verify(todo, ctx.cwd, signal, update);
      // Never append through a context whose session is being replaced.
      sessionSignal.throwIfAborted();
      // Evidence is display-only in history; only the gate's live map grants completion.
      pi.appendEntry("local-todo-verification-v1", evidence);
      const current = await revalidate(ctx, signal);
      if (evidence.passed && !current.has(todo.id)) throw new Error("Worktree changed after verification; run todo verify again");
      if (!evidence.passed) throw new Error(`${evidence.reason ?? "Verification failed"}\n${formatEvidence(evidence)}`);
    } else {
      let next = applyAction(state, action, valid);
      const added = next.todos.filter(todo => todo.id >= state.nextId && todo.checks);
      if (added.length) {
        const cwd = await realpath(ctx.cwd);
        const approved = await approve(ctx, {
          toolName: "todo", input: { action: "add", items: added.map(({ text, checks }) => ({ text, checks })) }, cwd,
        }, "Approve these immutable completion checks. Declared commands run only in the restricted sandbox. Approval declares requirements, not a host/network permission grant.", signal ?? lifecycle.signal);
        if (!approved) throw new Error("Declaring completion checks requires explicit human approval; unavailable or cancelled approval is not consent");
        signal?.throwIfAborted();
        if (await realpath(ctx.cwd) !== cwd) throw new Error("Working directory changed during approval; declare the checks again");
        // Approval can wait while external tools edit; never commit its old snapshot.
        const fresh = await revalidate(ctx, signal);
        signal?.throwIfAborted();
        next = applyAction(state, action, fresh);
        for (const todo of next.todos.filter(todo => todo.id >= state.nextId && todo.checks)) {
          todo.declaration = { cwd, approvedAt: new Date().toISOString() };
        }
      }
      if (action.action !== "list") persist(next, ctx);
    }
    return structuredClone(state);
  };
  pi.on("session_start", (_event, ctx) => { lifecycle.abort(); return serial(() => { lifecycle = new AbortController(); reminded = false; restore(ctx); }); });
  pi.on("session_tree", (_event, ctx) => { lifecycle.abort(); return serial(() => { lifecycle = new AbortController(); reminded = false; restore(ctx); }); });
  pi.on("input", event => {
    if (event.source !== "extension") reminded = false;
  });
  pi.on("agent_end", (event, ctx) => {
    const signal = AbortSignal.any([lifecycle.signal, ...(ctx.signal ? [ctx.signal] : [])]);
    return serial(async () => {
      if (signal.aborted) return;
      try { await revalidate(ctx, signal); }
      catch (error) { if (signal.aborted) return; throw error; }
      // Only resume a normal final answer, never errors, cancellation or terminating tools.
      const last = event.messages.at(-1);
      if (last?.role !== "assistant" || last.stopReason !== "stop" || signal.aborted) return;
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
  });
  pi.on("session_compact", (event, ctx) => {
    const signal = lifecycle.signal;
    return serial(async () => {
      if (signal.aborted) return;
      // Compaction retains the branch and live process; it is not evidence restoration.
      try { await revalidate(ctx, signal); }
      catch (error) { if (signal.aborted) return; throw error; }
      needsSnapshot = state.nextId > 1;
      if (!needsSnapshot) return;
      // Only overflow retries need steering before continue(); other paths must not start another turn.
      pi.sendMessage(snapshotMessage(), event.willRetry ? { deliverAs: "steer" } : { triggerTurn: false });
      needsSnapshot = false;
    });
  });
  pi.on("session_shutdown", (_event, ctx) => { lifecycle.abort(); return serial(() => { gate.reset(); if (ctx.hasUI) ctx.ui.setWidget("local-todo", undefined); }); });
  pi.on("before_agent_start", () => {
    if (!needsSnapshot) return;
    needsSnapshot = false;
    // Pi persists this message in history instead of moving it on every request.
    return { message: snapshotMessage() };
  });

  pi.registerTool({
    name: "todo", label: "Todo", description: "Session-local tasks. list returns all; mutations return changed rows and removed IDs. add: text or atomic items batch (not both); batch IDs follow array order. update/remove require id. blockedBy references existing or earlier batch IDs; dependencies must finish before starting/completing a task. remove rejects referenced IDs; prune deletes completed tasks and their dependency edges; clear deletes ordinary tasks but cannot bypass incomplete declared checks. Optional checks on add are immutable human-approved {name,command} requirements; verify {id} actually runs them sandboxed (120s/check, 10MiB capture, 12KB/200-line excerpt). Only fresh successful evidence permits completing/removing/pruning gated tasks; ordinary tasks are unchanged. category: empty clears, omitted retains. activeForm is display-only.",
    promptSnippet: "Track tasks and dependencies",
    promptGuidelines: ["Use todo for multi-step work or requested lists, not trivial tasks. Batch related additions; use short titles and optional categories. Update after verified progress. Never clear unfinished tasks without user approval. Use list only when the current state is missing."],
    parameters: Type.Object({
      action: StringEnum(["list", "add", "update", "remove", "prune", "clear", "verify"] as const),
      items: Type.Optional(Type.Array(Type.Object({
        text: Type.String({ minLength: 1, maxLength: 200 }),
        checks: Type.Optional(checksSchema()),
        category: Type.Optional(Type.String({ maxLength: 60, description: "Task category; empty string means uncategorized" })),
        status: Type.Optional(StringEnum(["pending", "in_progress", "completed"] as const)),
        activeForm: Type.Optional(Type.String({ minLength: 1, maxLength: 100 })),
        blockedBy: Type.Optional(Type.Array(Type.Integer({ minimum: 1, maximum: 999999 }), { maxItems: 50 })),
      }, { additionalProperties: false }), { minItems: 1, maxItems: 50, description: "Atomic batch for add only; cannot combine with top-level task fields. IDs are assigned in array order." })),
      checks: Type.Optional(checksSchema()),
      id: Type.Optional(Type.Integer({ minimum: 1, maximum: 999999 })),
      text: Type.Optional(Type.String({ minLength: 1, maxLength: 200 })),
      category: Type.Optional(Type.String({ maxLength: 60, description: "Category for add/update; empty string clears it, omit to retain" })),
      status: Type.Optional(StringEnum(["pending", "in_progress", "completed"] as const)),
      activeForm: Type.Optional(Type.String({ minLength: 1, maxLength: 100, description: "Nonempty activity label while in progress; omit to retain existing label" })),
      blockedBy: Type.Optional(Type.Array(Type.Integer({ minimum: 1, maximum: 999999 }), { maxItems: 50 })),
    }, { additionalProperties: false }),
    async execute(_id, params, signal, onUpdate, ctx) {
      const bounded = AbortSignal.any([lifecycle.signal, ...(signal ? [signal] : [])]);
      return serial(async () => {
        bounded.throwIfAborted();
        const before = state;
        const snapshot = await run(params, ctx, bounded, text => onUpdate?.({ content: [{ type: "text", text }], details: { state: structuredClone(state), action: params.action } }));
        const evidence = params.action === "verify" ? gate.details(params.id!) : undefined;
        const text = evidence
          ? `Verification passed for the current worktree.\n${formatEvidence(evidence)}\n${changes(before, snapshot)}`
          : params.action === "list" || needsSnapshot ? `Todo snapshot:\n${formatTodos(snapshot)}` : changes(before, snapshot);
        needsSnapshot = false;
        return { content: [{ type: "text" as const, text }], details: { state: snapshot, action: params.action, ...(params.action === "verify" ? { evidence: gate.details(params.id!) } : {}) } };
      });
    },
    renderCall(args, theme) {
      return new Text(theme.fg("toolTitle", theme.bold("Todo ")) + safe(String(args.action ?? "")) + (args.id ? ` #${args.id}` : ""), 0, 0);
    },
    renderResult(result, { expanded }, theme) {
      const snapshot = parseState(result.details?.state);
      const text = snapshot ? expanded ? `${formatTodos(snapshot)}${result.details?.evidence ? `\n${formatEvidence(result.details.evidence)}` : ""}` : `✓ ${snapshot.todos.filter(t => t.status === "completed").length}/${snapshot.todos.length} completed` : result.content.filter(c => c.type === "text").map(c => c.text).join("\n");
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
      if (command === "list") {
        const signal = lifecycle.signal;
        await serial(async () => {
          if (signal.aborted) return;
          try { await revalidate(ctx, signal); }
          catch (error) { if (signal.aborted) return; throw error; }
          ctx.ui.notify(formatTodos(state), "info");
        });
        return;
      }
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
          else if (command === "verify") action = { action: "verify", id };
          else if (command === "start" || command === "done" || command === "pending") action = { action: "update", id, status: command === "start" ? "in_progress" : command === "done" ? "completed" : "pending" };
          else throw new Error("Unknown command. Use /todo help for usage.");
        }
        const before = state;
        const signal = lifecycle.signal;
        const snapshot = await serial(() => run(action, ctx, signal));
        pi.sendMessage(needsSnapshot ? snapshotMessage() : {
          customType: CONTEXT, display: false, content: `Todo update (manual):\n${changes(before, snapshot)}`,
        }, { triggerTurn: false });
        needsSnapshot = false;
        ctx.ui.notify("Todos updated.", "info");
      } catch (error) { ctx.ui.notify(error instanceof Error ? error.message : String(error), "error"); }
    },
  });
}

export default function todoExtension(pi: ExtensionAPI) {
  registerTodo(pi);
}
