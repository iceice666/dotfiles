import { describe, expect, test } from "bun:test";
import { loadExtensions } from "../../agent-team/tests/sdk.ts";
import { SessionManager } from "@earendil-works/pi-coding-agent";
import { visibleWidth } from "@earendil-works/pi-tui";

async function setup() {
  const loaded = await loadExtensions([`${import.meta.dir}/../index.ts`], process.cwd());
  expect(loaded.errors).toEqual([]);
  const ext = loaded.extensions[0];
  const branch: any[] = [];
  const widgets = new Map();
  const notices: string[] = [];
  const messages: any[] = [];
  loaded.runtime.sendMessage = (message: any, options: any) => { messages.push({ message, options }); };
  loaded.runtime.getActiveTools = () => ["todo"];
  const theme = { fg: (_: string, text: string) => text, bold: (s: string) => s, strikethrough: (s: string) => s };
  const ctx: any = {
    hasUI: true, mode: "tui", isIdle: () => true, hasPendingMessages: () => false,
    sessionManager: { getBranch: () => branch },
    ui: { theme, setWidget: (key: string, value: any) => widgets.set(key, value), notify: (text: string) => notices.push(text), confirm: async () => true },
  };
  loaded.runtime.appendEntry = (customType: string, data: any) => { branch.push({ type: "custom", customType, data }); };
  const event = async (name: string, data = {}) => {
    let result: any;
    for (const handler of ext.handlers.get(name) ?? []) result = await handler(data, ctx);
    return result;
  };
  const tool = ext.tools.get("todo")!.definition;
  const call = (params: any, signal?: AbortSignal) => tool.execute("test", params, signal, undefined, ctx);
  const command = (args: string) => ext.commands.get("todo")!.handler(args, ctx);
  await event("session_start");
  return { loaded, ext, branch, widgets, notices, messages, ctx, event, call, command, theme };
}

describe("todo extension host integration", () => {
  test("unfinished todos trigger one follow-up per user input, including headless mode", async () => {
    const s = await setup();
    s.ctx.hasUI = false;
    const end = () => s.event("agent_end", { messages: [{ role: "assistant", stopReason: "stop" }] });
    await end();
    expect(s.messages).toHaveLength(0);
    await s.call({ action: "add", items: [{ text: "Pending" }, { text: "Working", status: "in_progress" }, { text: "Done", status: "completed" }] });
    await end();
    expect(s.messages).toHaveLength(1);
    expect(s.messages[0].options).toEqual({ triggerTurn: true, deliverAs: "followUp" });
    expect(s.messages[0].message.content).toContain("2 unfinished");
    expect(s.messages[0].message.content).toContain("Pending");
    expect(s.messages[0].message.content).toContain("Working");
    expect(s.messages[0].message.content).not.toContain("#3");
    await s.event("input", { source: "extension" });
    await s.event("session_compact");
    await end();
    expect(s.messages).toHaveLength(1);
    await s.event("input", { source: "interactive" });
    await end();
    expect(s.messages).toHaveLength(2);
    await s.call({ action: "update", id: 1, status: "completed" });
    await s.call({ action: "update", id: 2, status: "completed" });
    await s.event("input", { source: "rpc" });
    await end();
    expect(s.messages).toHaveLength(2);
  });
  test("reminders preserve dependencies on completed tasks without changing state", async () => {
    const s = await setup();
    await s.call({ action: "add", items: [
      { text: "Completed prerequisite", status: "completed" },
      { text: "Working dependent", status: "in_progress", blockedBy: [1] },
      { text: "Pending dependent", blockedBy: [1, 2] },
    ] });
    const before = (await s.call({ action: "list" })).details.state;
    const history = structuredClone(s.branch);
    const end = () => s.event("agent_end", { messages: [{ role: "assistant", stopReason: "stop" }] });
    await end();
    expect(s.messages).toHaveLength(1);
    const content = s.messages[0].message.content;
    expect(content).toContain("2 unfinished");
    expect(content).toContain("#2 [In progress] Working dependent; depends on: #1");
    expect(content).toContain("#3 [Pending] Pending dependent; depends on: #1, #2");
    expect(content).not.toContain("Completed prerequisite");
    await end();
    expect(s.messages).toHaveLength(1);
    expect((await s.call({ action: "list" })).details.state).toEqual(before);
    expect(s.branch).toEqual(history);
    await s.event("session_start");
    await end();
    expect(s.messages).toHaveLength(2);
    expect(s.messages[1].message.content).toBe(content);
  });
  test("reminders respect aborts, errors, terminating tools, queued messages and disabled todo", async () => {
    const s = await setup();
    await s.call({ action: "add", text: "Unfinished" });
    for (const stopReason of ["aborted", "error", "length", "toolUse"]) {
      await s.event("agent_end", { messages: [{ role: "assistant", stopReason }] });
    }
    await s.event("agent_end", { messages: [] });
    await s.event("agent_end", { messages: [{ role: "assistant", stopReason: "toolUse" }, { role: "toolResult" }] });
    const end = () => s.event("agent_end", { messages: [{ role: "assistant", stopReason: "stop" }] });
    s.ctx.signal = AbortSignal.abort();
    await end();
    s.ctx.signal = undefined;
    s.ctx.hasPendingMessages = () => true;
    await end();
    s.ctx.hasPendingMessages = () => false;
    s.loaded.runtime.getActiveTools = () => [];
    await end();
    expect(s.messages).toHaveLength(0);
    s.loaded.runtime.getActiveTools = () => ["todo"];
    await end();
    expect(s.messages).toHaveLength(1);
    // A new/restored session and tree navigation do not retain another run's guard.
    for (const name of ["session_start", "session_tree"]) {
      await s.event(name);
      await end();
    }
    expect(s.messages).toHaveLength(3);
  });
  test("loads against installed Pi and registers commands/tool", async () => {
    const s = await setup();
    expect(s.ext.commands.has("todos")).toBe(true);
    expect(s.ext.shortcuts.has("ctrl+shift+t")).toBe(false);
    expect((await s.call({ action: "list" })).details.state.todos).toEqual([]);
  });
  test("batch add persists and paints once; failures and aborts preserve the snapshot", async () => {
    const s = await setup();
    let paints = 0;
    const setWidget = s.ctx.ui.setWidget;
    s.ctx.ui.setWidget = (...args: any[]) => { paints++; setWidget(...args); };
    const items = [{ text: "甲" }, { text: "乙", blockedBy: [1] }];
    const result = await s.call({ action: "add", items });
    expect(result.details.state.todos.map((t: any) => t.id)).toEqual([1, 2]);
    expect(s.branch).toHaveLength(1);
    expect(paints).toBe(1);
    await expect(s.call({ action: "add", items: [{ text: "丙" }, { text: "" }] })).rejects.toThrow();
    await expect(s.call({ action: "add", items }, AbortSignal.abort())).rejects.toThrow();
    expect(s.branch).toHaveLength(1);
    expect(paints).toBe(1);
    await s.event("session_start");
    expect((await s.call({ action: "list" })).details.state).toEqual(result.details.state);
    await Promise.all([
      s.call({ action: "add", items: [{ text: "丙" }, { text: "丁" }] }),
      s.call({ action: "add", text: "戊" }),
    ]);
    expect((await s.call({ action: "list" })).details.state.todos.map((t: any) => t.id)).toEqual([1, 2, 3, 4, 5]);
    s.branch.splice(1);
    await s.event("session_tree");
    expect((await s.call({ action: "list" })).details.state).toEqual(result.details.state);
  });
  test("parallel calls preserve state; reload/tree use branch custom entries", async () => {
    const s = await setup();
    await Promise.all([s.call({ action: "add", text: "甲" }), s.call({ action: "add", text: "乙" })]);
    expect(s.branch).toHaveLength(2);
    await s.event("session_start");
    expect((await s.call({ action: "list" })).details.state.todos).toHaveLength(2);
    s.branch.pop();
    await s.event("session_tree");
    expect((await s.call({ action: "list" })).details.state.todos).toHaveLength(1);
    await s.event("session_compact");
    expect((await s.call({ action: "list" })).details.state.todos[0].text).toBe("甲");
    s.branch.length = 0;
    await s.event("session_start");
    expect((await s.call({ action: "list" })).details.state.todos).toHaveLength(0);
  });
  test("real SessionManager branches and compaction retain the correct snapshot", async () => {
    const s = await setup();
    const sm = SessionManager.inMemory(process.cwd());
    s.ctx.sessionManager = sm;
    s.loaded.runtime.appendEntry = (type: string, data: any) => { sm.appendCustomEntry(type, data); };
    await s.call({ action: "add", text: "第一項" });
    const first = sm.getLeafId()!;
    await s.call({ action: "add", text: "另一分支" });
    sm.branch(first);
    await s.event("session_tree");
    expect((await s.call({ action: "list" })).details.state.todos.map((t: any) => t.text)).toEqual(["第一項"]);
    sm.appendCompaction("摘要", first, 1000);
    await s.event("session_compact");
    expect((await s.call({ action: "list" })).details.state.todos).toHaveLength(1);
    sm.appendCustomEntry("local-todo-state-v1", { version: 99 });
    await s.event("session_start");
    expect((await s.call({ action: "list" })).details.state.todos).toHaveLength(1);
    expect(s.notices.some(text => text.includes("corrupted"))).toBe(true);
  });
  test("RPC widget follows collapse and expand commands", async () => {
    const s = await setup();
    s.ctx.mode = "rpc";
    await s.command("add RPC 任務");
    await s.command("collapse");
    expect(s.widgets.get("local-todo")).toEqual([" TODO", "  └─ Tasks · 0/1"]);
    await s.command("expand");
    expect(s.widgets.get("local-todo")).toEqual([" TODO", "  └─ Tasks · 0/1", "     └─ ☐ RPC 任務"]);
  });
  test("tree colors and display pruning preserve data and completion order across restore", async () => {
    const s = await setup();
    const render = (theme = s.theme) => s.widgets.get("local-todo")({ terminal: { rows: 60 } }, theme).render(200);
    await s.call({ action: "add", text: "First" });
    await s.call({ action: "add", text: "Second" });
    await s.call({ action: "add", text: "Waiting", blockedBy: [1] });
    expect(render()).toEqual([" TODO", "  └─ Tasks · 0/3", "     ├─ ☐ First", "     ├─ ☐ Second", "     └─ ☐ Waiting (blocked)"]);
    const colored = { ...s.theme, fg: (kind: string, text: string) => `<${kind}>${text}</${kind}>` };
    expect(render(colored).join("\n")).toContain("<warning>☐ Waiting (blocked)</warning>");
    expect(render(colored).join("\n")).toContain("<text>☐ First</text>");
    await s.call({ action: "update", id: 2, status: "completed" });
    await s.call({ action: "update", id: 1, status: "completed" });
    const expected = [" TODO", "  └─ Tasks · 2/3", "     ├─ ☑ First", "     └─ ☐ Waiting"];
    expect(render()).toEqual(expected);
    expect(render(colored).join("\n")).toContain("<success>☑ First</success>");
    await s.event("session_start");
    expect(render()).toEqual(expected);
    await s.event("session_compact");
    expect(render()).toEqual(expected);
    expect((await s.call({ action: "list" })).details.state.todos).toHaveLength(3);
    expect((await s.event("context", { messages: [] })).messages[0].content).toContain("Second");
    await s.call({ action: "update", id: 1, status: "pending" });
    expect(render().join("\n")).toContain("☑ Second");
    expect(render().join("\n")).toContain("Waiting (blocked)");
    s.branch.pop();
    await s.event("session_tree");
    expect(render()).toEqual(expected);
    await s.call({ action: "prune" });
    expect(render()).toEqual([" TODO", "  └─ Tasks · 0/1", "     └─ ☐ Waiting"]);
    await s.call({ action: "update", id: 3, status: "completed" });
    expect(render()).toEqual([" TODO", "  └─ Tasks · 1/1", "     └─ ☑ Waiting"]);
    await s.call({ action: "clear" });
    expect(s.widgets.get("local-todo")).toBeUndefined();
  });
  test("categories render a tree with per-category progress and survive restore", async () => {
    const s = await setup();
    const render = () => s.widgets.get("local-todo")({ terminal: { rows: 60 } }, s.theme).render(200);
    await s.call({ action: "add", items: [
      { text: "Translate UI", category: "UI", status: "completed" },
      { text: "Run UI test", category: "Verify", status: "completed" },
    ] });
    const expected = [" TODO", "  ├─ UI (1/1)", "  │  └─ ☑ Translate UI", "  └─ Verify (1/1)", "     └─ ☑ Run UI test"];
    expect(render()).toEqual(expected);
    for (const name of ["session_start", "session_tree", "session_compact"]) {
      await s.event(name);
      expect(render()).toEqual(expected);
    }
    expect((await s.event("context", { messages: [] })).messages[0].content).toContain("[Category: UI]");
    await s.command("category 2 UI");
    expect(render()).toEqual([" TODO", "  └─ UI (2/2)", "     └─ ☑ Run UI test"]);
    await s.command("category 2");
    expect(render().join("\n")).toContain("Uncategorized (1/1)");
    await s.command("collapse");
    expect(render()).toEqual([" TODO", "  ├─ UI (1/1)", "  └─ Uncategorized (1/1)"]);
    s.ctx.mode = "rpc";
    await s.command("expand");
    expect(s.widgets.get("local-todo").join("\n")).toContain("☑ Run UI test");
    await s.command("category 1");
    expect(s.widgets.get("local-todo").join("\n")).toContain("Tasks · 2/2");
  });
  test("categorized panels bound headers and tasks, preserve full lists and task styling", async () => {
    const s = await setup();
    await s.call({ action: "add", items: [
      { text: "First", category: "UI" },
      { text: "Blocked", category: "UI", blockedBy: [1] },
      { text: "Working", category: "Verify", status: "in_progress", activeForm: "Running tests" },
    ] });
    const colored = { ...s.theme, fg: (kind: string, text: string) => `<${kind}>${text}</${kind}>` };
    const tree = s.widgets.get("local-todo")({ terminal: { rows: 60 } }, colored).render(200).join("\n");
    expect(tree).toContain("<warning>☐ Blocked (blocked)</warning>");
    expect(tree).toContain("<text>☐ Running tests</text>");
    for (let i = 0; i < 20; i++) await s.call({ action: "add", text: "繁體中文🚀".repeat(10), category: `Phase ${i}` });
    const render = (width: number) => s.widgets.get("local-todo")({ terminal: { rows: 24 } }, s.theme).render(width);
    expect(render(80).length).toBeLessThanOrEqual(8);
    expect(render(80).join("\n")).toContain("more rows · /todos");
    for (const width of [0, 1, 5, 20, 80]) for (const line of render(width)) expect(visibleWidth(line)).toBeLessThanOrEqual(width);
    await s.command("collapse");
    expect(render(80).length).toBeLessThanOrEqual(8);
    expect(render(80).join("\n")).toContain("more categories · /todos");
    expect((await s.call({ action: "list" })).details.state.todos).toHaveLength(23);
    const schema: any = s.ext.tools.get("todo")!.definition.parameters;
    expect(schema.properties.category.maxLength).toBe(60);
    expect(schema.properties.items.items.properties.category.maxLength).toBe(60);
  });
  test("failed/aborted operations never persist", async () => {
    const s = await setup();
    await expect(s.call({ action: "add", text: "" })).rejects.toThrow();
    await expect(s.call({ action: "add", text: "取消" }, AbortSignal.abort())).rejects.toThrow();
    expect(s.branch).toHaveLength(0);
  });
  test("commands, confirmation cancellation, busy protection and context refresh", async () => {
    const s = await setup();
    await s.command("add 撰寫測試");
    await s.command("start 1");
    expect((await s.call({ action: "list" })).details.state.todos[0].status).toBe("in_progress");
    s.ctx.ui.confirm = async () => false;
    await s.command("clear");
    s.ctx.isIdle = () => false;
    await s.command("done 1");
    expect(s.branch).toHaveLength(2);
    const result = await s.event("context", { messages: [] });
    expect(result.messages[0].content).toContain("撰寫測試");
    expect((await s.event("context", result)).messages).toHaveLength(1);
  });
  test("widget respects row/width budgets, collapse, Unicode and headless mode", async () => {
    const s = await setup();
    for (let i = 0; i < 12; i++) await s.call({ action: "add", text: "繁體中文🚀".repeat(10) });
    const render = (width: number) => s.widgets.get("local-todo")({ terminal: { rows: 24 } }, s.theme).render(width);
    expect(render(80).length).toBeLessThanOrEqual(8);
    expect(render(80).at(-1)).toBe("     └─ … 8 more · /todos");
    expect(render(80)).not.toContain("  └─────");
    for (const width of [0, 1, 5, 20, 80]) for (const line of render(width)) expect(visibleWidth(line)).toBeLessThanOrEqual(width);
    await s.command("collapse");
    expect(render(80)).toEqual([" TODO", "  └─ Tasks · 0/12"]);
    s.ctx.hasUI = false;
    s.ctx.mode = "print";
    s.ctx.ui.setWidget = () => { throw new Error("headless UI call"); };
    await s.call({ action: "add", text: "Headless" });
    await s.event("session_start");
  });
});
