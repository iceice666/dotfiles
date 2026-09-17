import { afterEach, expect, test } from "bun:test";
import { rmSync } from "node:fs";
import { dirname } from "node:path";
import { stripVTControlCharacters } from "node:util";

const cleanups: Array<() => Promise<void>> = [];
afterEach(async () => { for (const cleanup of cleanups.splice(0)) await cleanup(); });
import { loadExtensions } from "../../agent-team/tests/sdk.ts";

async function setup() {
  const loaded = await loadExtensions([`${import.meta.dir}/../index.ts`], process.cwd());
  expect(loaded.errors).toEqual([]);
  const ext = loaded.extensions[0];
  const messages: any[] = [], notices: string[] = [];
  const statuses = new Map();
  const ctx: any = { cwd: process.cwd(), hasUI: true, mode: "tui", ui: {
    notify: (s: string) => notices.push(s), setStatus: (k: string, v: any) => statuses.set(k, v),
  } };
  loaded.runtime.sendMessage = (message: any, options: any) => { messages.push({ message, options }); };
  const event = async (name: string) => { for (const handler of ext.handlers.get(name) ?? []) await handler({}, ctx); };
  await event("session_start");
  const tool = ext.tools.get("background_task")!.definition;
  const call = (params: any, signal?: AbortSignal) => tool.execute("test", params, signal, undefined, ctx);
  const command = (args: string) => ext.commands.get("bg")!.handler(args, ctx);
  const dirs = new Set<string>();
  const originalExecute = tool.execute;
  tool.execute = async (...args: any[]) => {
    const result: any = await originalExecute(...args);
    for (const task of result.details.tasks) dirs.add(dirname(task.logPath));
    return result;
  };
  cleanups.push(async () => {
    await event("session_shutdown");
    for (const dir of dirs) rmSync(dir, { recursive: true, force: true });
  });
  return { ctx, messages, statuses, notices, call, command, event, ext };
}
async function until(check: () => boolean) {
  const end = Date.now() + 5000;
  while (!check()) { if (Date.now() > end) throw new Error("Timed out"); await Bun.sleep(20); }
}
test("loads in installed Pi, starts asynchronously, queues completion without triggering model", async () => {
  const s = await setup();
  try {
    const result: any = await s.call({ action: "start", command: "sleep 0.1; printf 'hello background'" });
    const id = result.details.tasks[0].id;
    expect(result.content[0].text).toContain("not a completion result");
    expect(s.statuses.get("background-task")).toBe("BG 1");
    await until(() => s.messages.length > 0);
    expect(s.messages[0].options).toEqual({ deliverAs: "nextTurn" });
    expect(s.messages[0].message.details.status).toBe("completed");
    expect((await s.call({ action: "output", id })).content[0].text).toContain("hello background");
    expect(s.statuses.get("background-task")).toBeUndefined();
  } finally { await s.event("session_shutdown"); }
});
test("command preserves shell quoting and supports output/list/stop", async () => {
  const s = await setup();
  try {
    await s.command("start printf '%s' 'hello world'; sleep 30");
    const result: any = await s.call({ action: "list" });
    const id = result.details.tasks[0].id;
    expect(result.details.tasks[0].command).toBe("printf '%s' 'hello world'; sleep 30");
    await s.command(`output ${id} 0`);
    expect(s.notices.some(t => t.includes("lines"))).toBe(true);
    await s.command(`stop ${id}`);
    expect((await s.call({ action: "list" }) as any).details.tasks[0].status).toBe("stopped");
    await s.command("help");
    expect(s.messages.at(-1).message.content).toContain("/bg start");
  } finally { await s.event("session_shutdown"); }
});
test("abort before start prevents spawn; shutdown suppresses completion and rejects new work", async () => {
  const s = await setup();
  await expect(s.call({ action: "start", command: "sleep 30" }, AbortSignal.abort())).rejects.toThrow();
  expect((await s.call({ action: "list" }) as any).details.tasks).toEqual([]);
  await s.call({ action: "start", command: "sleep 30" });
  await s.event("session_shutdown");
  await s.event("session_shutdown");
  expect(s.messages).toEqual([]);
  await expect(s.call({ action: "start", command: "true" })).rejects.toThrow("shut down");
});
test("headless tools do not access UI; missing arguments and bad IDs fail", async () => {
  const s = await setup();
  s.ctx.hasUI = false;
  s.ctx.ui = new Proxy({}, { get() { throw new Error("Unexpected UI"); } });
  try {
    await expect(s.call({ action: "start" })).rejects.toThrow("command");
    await expect(s.call({ action: "output" })).rejects.toThrow("id");
    await expect(s.call({ action: "stop", id: "unknown" })).rejects.toThrow();
    await s.call({ action: "start", command: "sleep 30" });
    await s.command("stop-all");
  } finally { await s.event("session_shutdown"); }
});

test("wait returns bounded final output and terminal failure without requiring UI", async () => {
  const s = await setup();
  s.ctx.hasUI = false;
  s.ctx.mode = "print";
  s.ctx.ui = new Proxy({}, { get() { throw new Error("Unexpected UI"); } });
  const started: any = await s.call({ action: "start", command: "printf 'first\\nlast\\n'; exit 9" });
  const id = started.details.tasks[0].id;
  const result: any = await s.call({ action: "wait", id, lines: 1 });
  expect(result.details.wait.outcome).toBe("finished");
  expect(result.details.wait.task.exitCode).toBe(9);
  expect(result.details.wait.task.status).toBe("failed");
  expect(result.content[0].text.endsWith("\nlast")).toBe(true);
  expect((await s.call({ action: "wait", id }) as any).details.wait.outcome).toBe("finished");
});
test("wait timeout/abort leave jobs running and shutdown settles an outstanding wait", async () => {
  const s = await setup();
  const started: any = await s.call({ action: "start", command: "sleep 30" });
  const id = started.details.tasks[0].id;
  await expect(s.call({ action: "wait" })).rejects.toThrow("id");
  await expect(s.call({ action: "wait", id: "missing" })).rejects.toThrow("Unknown");
  await expect(s.call({ action: "wait", id, timeout: 0 })).rejects.toThrow("timeout");
  await expect(s.call({ action: "wait", id, lines: 0 })).rejects.toThrow("lines");
  const timed: any = await s.call({ action: "wait", id, timeout: 0.01 });
  expect(timed.details.wait.outcome).toBe("timed_out");
  expect(timed.details.wait.task.status).toBe("running");
  const controller = new AbortController();
  const waiting = s.call({ action: "wait", id }, controller.signal);
  controller.abort();
  const aborted: any = await waiting;
  expect(aborted.details.wait.outcome).toBe("aborted");
  expect(aborted.content[0].text).toContain("job was not stopped");
  expect(aborted.details.wait.task.status).toBe("running");
  const shutdownWait = s.call({ action: "wait", id });
  await s.event("session_shutdown");
  expect((await shutdownWait as any).details.wait.task.status).toBe("stopped");
  expect(s.messages).toEqual([]);
});

function mockPanel(s: Awaited<ReturnType<typeof setup>>) {
  let component: any;
  let renders = 0;
  const terminal = { rows: 40 };
  s.ctx.ui.custom = (factory: any, options: any) => {
    expect(options.overlay).toBe(true);
    return new Promise<void>(resolve => {
      component = factory({ terminal, requestRender: () => renders++ },
        { fg: (_: string, text: string) => text, bold: (text: string) => text },
        { matches: (data: string) => data === "\x1b" }, resolve);
    });
  };
  return { get component() { return component; }, get renders() { return renders; }, terminal };
}
test("panel opens empty without model messages, refreshes, closes and disposes timer", async () => {
  const s = await setup(), view = mockPanel(s);
  const opened = s.command("");
  expect(view.component.render(90).join("\n")).toContain("No background tasks");
  expect(s.messages).toEqual([]);
  await Bun.sleep(300);
  expect(view.renders).toBeGreaterThan(0);
  view.component.handleInput("\x1b");
  await opened;
  const renders = view.renders;
  await Bun.sleep(300);
  expect(view.renders).toBe(renders);
  const reopened = s.ext.shortcuts.get("ctrl+shift+b")!.handler(s.ctx);
  expect(view.component.render(90).join("\n")).toContain("LIVE");
  await s.event("session_shutdown");
  await reopened;
});
test("live output, snapshot scrolling, switching tasks and narrow layout", async () => {
  const s = await setup(), view = mockPanel(s);
  const result: any = await s.call({ action: "start", command: "for i in $(seq 1 60); do echo line-$i; done; sleep 0.3; echo later; sleep 30" });
  const id = result.details.tasks[0].id;
  const opened = s.command("panel");
  await until(() => view.component.render(100).some((line: string) => /^│later\s*│$/.test(line)));
  expect(view.component.render(100).join("\n")).toContain("PID");
  view.component.handleInput("\x1b[5~");
  expect(view.component.render(100).join("\n")).toContain("PAUSED snapshot");
  view.component.handleInput("\x1b[H");
  expect(view.component.render(100).join("\n")).toContain("line-1");
  view.component.handleInput("f");
  expect(view.component.render(100).join("\n")).toContain("later");
  await s.call({ action: "start", command: "echo second; sleep 30" });
  view.component.handleInput("\x1b[B");
  expect(view.component.render(100).join("\n")).toContain("Task 2/2");
  for (const width of [1, 3, 20, 80]) {
    const lines = view.component.render(width);
    expect(lines.every((line: string) => [...stripVTControlCharacters(line)].length <= width)).toBe(true);
    expect(lines.length).toBeLessThanOrEqual(34);
  }
  view.terminal.rows = 8;
  expect(view.component.render(40)).toHaveLength(1);
  view.component.handleInput("q");
  await opened;
  expect((await s.call({ action: "list" }) as any).details.tasks.find((t: any) => t.id === id).status).toBe("running");
});
test("non-TUI panel gives guidance and bare bg retains list fallback", async () => {
  const s = await setup();
  s.ctx.mode = "rpc";
  await s.command("panel");
  expect(s.notices.at(-1)).toContain("requires TUI");
  await s.command("");
  expect(s.messages.at(-1).message.content).toBe("No background tasks.");
});
