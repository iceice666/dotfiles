import { afterEach, beforeEach, expect, test } from "bun:test";
import extension, { approveAction } from "../index.ts";
import { loadExtensions } from "../../agent-team/tests/sdk.ts";

const teamKeys = ["PI_TEAM_AGENT", "PI_TEAM_URL", "PI_TEAM_TOKEN"] as const;
let savedEnv: Array<string | undefined> = [];
beforeEach(() => { savedEnv = teamKeys.map(key => process.env[key]); for (const key of teamKeys) delete process.env[key]; });
afterEach(() => { teamKeys.forEach((key, i) => { if (savedEnv[i] === undefined) delete process.env[key]; else process.env[key] = savedEnv[i]; }); });

function setup(mode = "print") {
  const handlers = new Map<string, any>();
  const commands = new Map<string, any>();
  const calls: any[] = [];
  const pi: any = { on: (n: string, h: any) => handlers.set(n, h), registerCommand: (n: string, c: any) => commands.set(n, c) };
  const ctx: any = {
    cwd: process.cwd(), mode, hasUI: mode !== "print",
    model: { provider: "test", id: "reviewer", maxTokens: 4096 },
    modelRegistry: { complete: async (...args: any[]) => { calls.push(args); return { stopReason: "stop", content: [{ type: "text", text: '{"decision":"allow","reason":"routine"}' }] }; } },
    ui: { notify() {}, setStatus() {} },
  };
  extension(pi);
  return { ctx, calls, handlers, commands, event: (n: string, e: any = {}) => handlers.get(n)?.(e, ctx) };
}

test("loads against the pinned actual SDK", async () => {
  const events: any = { emit() {}, on() { return () => {}; } };
  const loaded = await loadExtensions([`${import.meta.dir}/../index.ts`], process.cwd(), events);
  expect(loaded.errors).toEqual([]);
  expect(loaded.extensions).toHaveLength(1);
});

test("default on, current model, tool hook actually reviews raw command", async () => {
  const s = setup();
  const input = { command: "git status\nprintf marker" };
  expect(await s.event("tool_call", { toolName: "bash", input })).toBeUndefined();
  expect(s.calls).toHaveLength(1);
  expect(s.calls[0][0]).toBe(s.ctx.model);
  expect(JSON.stringify(s.calls[0][1])).toContain("git status");
});

test("interactive provenance only; RPC and extension tasks are not human grants", async () => {
  for (const source of ["interactive", "rpc", "extension"]) {
    const s = setup("tui");
    await s.event("input", { text: "deploy", source });
    await s.event("tool_call", { toolName: "bash", input: { command: "deploy" } });
    const message = s.calls[0][1].messages[0].content;
    expect(JSON.parse(message[0].text).task.human).toBe(source === "interactive");
  }
});

test("headless session cannot disable guard", async () => {
  const s = setup();
  await s.commands.get("auto").handler("off", s.ctx);
  await s.event("tool_call", { toolName: "bash", input: { command: "test" } });
  expect(s.calls).toHaveLength(1);
});

test("shutdown cancels later tools", async () => {
  const s = setup(); await s.event("session_shutdown");
  expect((await s.event("tool_call", { toolName: "bash", input: { command: "test" } })).block).toBe(true);
  expect(s.calls).toHaveLength(0);
});

test("human approval must be exact selected label, never free text; full payload displayed", async () => {
  for (const response of [undefined, "1. 拒絕", "2. 僅允許這次操作", "Other: enter your own answer"]) {
    let title = "";
    const ctx: any = { mode: "rpc", hasUI: true, ui: {
      select: async (t: string) => { title = t; return response; }, input: async () => "僅允許這次操作",
    } };
    const action = { toolName: "write", cwd: process.cwd(), input: { path: "file", content: "ALL CONTENT END" } };
    expect(await approveAction(ctx, action, "review", new AbortController().signal)).toBe(response === "2. 僅允許這次操作");
    expect(title).toContain("ALL CONTENT END");
  }
});
