import { afterEach, beforeEach, expect, test } from "bun:test";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import extension from "../index.ts";
// Tests run from the repository checkout; production attests the managed Nix tree and sandbox.
const confined = { attest: () => ({ confined: true, reason: "" }) };
import { requestParentContext } from "../service.ts";
import { executionDecision } from "../../execution-policy/index.ts";
import { approveAction } from "../index.ts";
import { Team, autoModeActionId } from "../../agent-team/team.mjs";

const keys = ["PI_TEAM_AGENT", "PI_TEAM_URL", "PI_TEAM_TOKEN"];
let previous: Array<string | undefined>;
const cleanup: Array<() => Promise<void>> = [];
beforeEach(() => { previous = keys.map(key => process.env[key]); keys.forEach(key => delete process.env[key]); });
afterEach(async () => { for (const close of cleanup.splice(0).reverse()) await close(); keys.forEach((key, i) => { if (previous[i] === undefined) delete process.env[key]; else process.env[key] = previous[i]; }); });
function setup(mode = "tui") {
  const handlers = new Map<string, any>(), commands = new Map<string, any>();
  let modelCalls = 0;
  const ctx: any = { mode, hasUI: false, cwd: process.cwd(), sessionManager: { getSessionId: () => "test", getBranch: () => [], getLeafId: () => null },
    model: { provider: "test", id: "test", maxTokens: 2048 }, modelRegistry: { complete: async () => { modelCalls++; return { stopReason: "stop", content: [{ type: "text", text: '{"decision":"deny","reason":"unsafe"}' }] }; } },
    ui: { setStatus() {}, notify() {} } };
  extension({ on: (n: string, h: any) => handlers.set(n, h), registerCommand: (n: string, c: any) => commands.set(n, c), getAllTools: () => [] } as any, confined);
  const event = (n: string, e: any = {}) => handlers.get(n)?.(e, ctx);
  cleanup.push(async () => { await event("session_shutdown"); });
  return { ctx, event, command: (text: string) => commands.get("yolo").handler(text, ctx), auto: (text: string) => commands.get("auto").handler(text, ctx), calls: () => modelCalls };
}
const tool = { toolName: "bash", input: { command: "example" } };

test("parent YOLO bypasses only its own hook, off restores review, fresh instances default off", async () => {
  const s = setup(); await s.event("session_start");
  expect((await s.event("tool_call", tool))?.block).toBe(true);
  await s.command("on");
  expect(await s.event("tool_call", tool)).toBeUndefined(); expect(s.calls()).toBe(1);
  await s.command("off");
  expect((await s.event("tool_call", tool))?.block).toBe(true); expect(s.calls()).toBe(2);
  await s.command("on"); await s.auto("on");
  expect((await s.event("tool_call", tool))?.block).toBe(true);
  await s.command("on"); await s.event("session_tree");
  expect((await s.event("tool_call", tool))?.block).toBe(true);
  const fresh = setup(); expect((await fresh.event("tool_call", tool))?.block).toBe(true);
});

test("YOLO leaves execution-policy and explicit verification approval intact", async () => {
  const s = setup(); await s.command("on");
  expect(await s.event("tool_call", { toolName: "unknown_executor", input: {} })).toBeUndefined();
  expect(executionDecision("unknown_executor")?.block).toBe(true);
  expect(await approveAction({ ...s.ctx, mode: "print", hasUI: false }, { ...tool, cwd: process.cwd() }, "Verify check declaration", new AbortController().signal)).toBe(false);
});

test("headless callers cannot enable YOLO", async () => {
  for (const mode of ["rpc", "print"]) {
    const s = setup(mode); await s.command("on");
    expect((await s.event("tool_call", tool))?.block).toBe(true);
  }
});

test("parent publishes mode for existing and new workers without action-grant changes", async () => {
  const s = setup(); await s.event("session_start");
  const action = { toolName: "auto_mode_status", input: {}, cwd: process.cwd() };
  const request = { ...action, actionId: autoModeActionId(action.toolName, action.input, action.cwd) };
  const read = () => requestParentContext("worker", request, new AbortController().signal);
  expect((await read()).yolo).toBe(false);
  await s.command("on"); const on = await read(); expect(on.yolo).toBe(true);
  await s.command("off"); const off = await read(); expect(off.yolo).toBe(false); expect(off.revision).toBeGreaterThan(on.revision);
});

async function worker(provider: (call: number) => any) {
  const dir = mkdtempSync(join(tmpdir(), "auto-yolo-")); let calls = 0;
  const team = new Team({ directory: dir, workspace: process.cwd(), extension: "/unused", deliverParent() {}, getAutoModeContext: () => provider(++calls) });
  await team.ready;
  team.agents.set("worker", { name: "worker", status: "running", rpc: { stop: async () => {} } });
  team.tokens.set("token", "worker");
  cleanup.push(async () => { await team.close(); rmSync(dir, { recursive: true, force: true }); });
  process.env.PI_TEAM_AGENT = "worker"; process.env.PI_TEAM_URL = team.url; process.env.PI_TEAM_TOKEN = "token";
  return { ...setup("rpc"), team };
}

test("worker skips Auto Mode under parent YOLO including large calls, cannot toggle it itself", async () => {
  const s = await worker(() => ({ revision: 1, yolo: true }));
  await s.command("off");
  expect(await s.event("tool_call", { toolName: "write", input: { path: "file", content: "x".repeat(40000) } })).toBeUndefined();
  expect(s.calls()).toBe(0);
});

test("worker never assumes YOLO on missing mode, lost broker, or mid-check revocation", async () => {
  for (const provider of [() => ({ revision: 1 }), (call: number) => ({ revision: call, yolo: call === 1 }), () => { throw new Error("offline"); }]) {
    const s = await worker(provider);
    expect((await s.event("tool_call", { toolName: "read", input: { path: ".env" } }))?.block).toBe(true);
    expect(s.calls()).toBe(0);
  }
});
