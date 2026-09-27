import { afterEach, beforeEach, expect, test } from "bun:test";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import extension from "../index.ts";
// Tests run from the repository checkout; production attests the managed Nix tree and sandbox.
const confined = { attest: () => ({ confined: true, reason: "" }) };
import { requestParentContext, registerParentContext, mergeParentContext } from "../service.ts";
import { autoModeActionId } from "../../agent-team/team.mjs";
import { guardTool } from "../gate.ts";
import type { ReviewContext } from "../classifier.ts";

let env: string | undefined;
let root: string;
beforeEach(() => { env = process.env.PI_TEAM_AGENT; delete process.env.PI_TEAM_AGENT; root = mkdtempSync(join(tmpdir(), "auto-parent-")); mkdirSync(join(root, ".git")); mkdirSync(join(root, "extensions")); writeFileSync(join(root, "extensions", "file.ts"), "old"); });
afterEach(() => { if (env === undefined) delete process.env.PI_TEAM_AGENT; else process.env.PI_TEAM_AGENT = env; rmSync(root, { recursive: true, force: true }); });
const tick = () => new Promise(resolve => setTimeout(resolve, 0));
function setup(mode = "tui") {
  const handlers = new Map<string, any>(), commands = new Map<string, any>();
  const views: any[] = [], notes: any[] = [];
  const entries = [{ id: "task", type: "message", message: { role: "user", content: "Implement local sandbox, no deploy" } }];
  const ctx: any = { cwd: root, mode, hasUI: mode !== "print", sessionManager: { getSessionId: () => "parent-test", getLeafId: () => entries.at(-1)?.id, getBranch: () => entries },
    ui: { notify: (...args: any[]) => notes.push(args), setStatus() {}, custom: (factory: any) => new Promise(resolve => views.push(factory({ requestRender() {}, terminal: { rows: 24, columns: 100 } }, { fg: (_: string, s: string) => s }, {}, resolve))) },
  };
  extension({ on: (n: string, h: any) => handlers.set(n, h), registerCommand: (n: string, c: any) => commands.set(n, c), getAllTools: () => [] } as any, confined);
  return { ctx, views, notes, entries, event: (n: string, e: any = {}) => handlers.get(n)?.(e, ctx), command: (s: string) => commands.get("auto").handler(s, ctx) };
}
const request = (includeContext = false) => {
  const action = { toolName: "write", input: { path: "extensions/file.ts", content: "new" }, cwd: root };
  return { ...action, actionId: autoModeActionId(action.toolName, action.input, action.cwd), includeContext };
};

test("scope grants need real UI; parent context transports no human authority; revoke clears worker match", async () => {
  const s = setup(); await s.event("session_start");
  try {
    expect((await requestParentContext("worker", request(), new AbortController().signal)).scopeId).toBeUndefined();
    const granting = s.command("grant extensions"); await tick();
    expect(s.views).toHaveLength(1);
    s.views[0].handleInput("\u001b[B"); s.views[0].handleInput("\r"); s.views[0].handleInput("\r");
    await granting;
    const result = await requestParentContext("worker", request(true), new AbortController().signal);
    expect(result.scopeId).toBeTruthy();
    expect(result.context?.recent[0].text).toContain("no deploy");
    expect(JSON.stringify(result.context)).not.toContain('"human":true');
    expect(await s.event("tool_call", { toolName: "write", input: request().input })).toBeUndefined();
    await s.command("revoke all");
    const after = await requestParentContext("worker", request(), new AbortController().signal);
    expect(after.scopeId).toBeUndefined(); expect(after.revision).toBeGreaterThan(result.revision);
  } finally { await s.event("session_shutdown"); }
});

test("cancelled grant and noninteractive grant never create scopes", async () => {
  for (const mode of ["tui", "rpc", "print"]) {
    const s = setup(mode); await s.event("session_start");
    try {
      const pending = s.command("grant extensions"); await tick();
      if (mode === "tui") s.views[0].handleInput("\u001b");
      await pending;
      expect((await requestParentContext("worker", request(), new AbortController().signal)).scopeId).toBeUndefined();
    } finally { await s.event("session_shutdown"); }
  }
});

test("branch navigation and restart expire scopes, no persisted grant", async () => {
  const s = setup(); await s.event("session_start");
  const granting = s.command("grant extensions"); await tick(); s.views[0].handleInput("\u001b[B"); s.views[0].handleInput("\r"); s.views[0].handleInput("\r"); await granting;
  expect((await requestParentContext("worker", request(), new AbortController().signal)).scopeId).toBeTruthy();
  await s.event("session_tree");
  expect((await requestParentContext("worker", request(), new AbortController().signal)).scopeId).toBeUndefined();
  await s.event("session_shutdown");
  await expect(requestParentContext("worker", request(), new AbortController().signal)).rejects.toThrow();
});

test("new parent structured answer changes worker revision without an input event", async () => {
  const s = setup(); await s.event("session_start");
  try {
    const before = await requestParentContext("worker", request(true), new AbortController().signal);
    s.entries.push({ id: "stop", type: "message", message: { role: "toolResult", toolName: "ask_user_question", content: JSON.stringify({ status: "answered", answers: [{ question: "Continue?", selected: ["Stop, read-only"] }] }) } } as any);
    const after = await requestParentContext("worker", request(true), new AbortController().signal);
    expect(after.revision).toBeGreaterThan(before.revision);
    expect(after.context?.recent.at(-1)?.text).toContain("read-only");
  } finally { await s.event("session_shutdown"); }
});

test("service replacement invalidates an in-flight response", async () => {
  let done!: () => void;
  const old = registerParentContext(async () => { await new Promise<void>(resolve => { done = resolve; }); return { revision: 1 }; });
  const pending = requestParentContext("worker", request(), new AbortController().signal);
  const next = registerParentContext(async () => ({ revision: 2 }));
  done(); await expect(pending).rejects.toThrow(); old(); next();
});

test("scopes never override hard block; revocation wins final recheck", async () => {
  let looked = false;
  const blocked = await guardTool("read", { path: ".env" }, root, { classify: async () => ({ decision: "allow", reason: "safe" }), approve: async () => true, scope: async () => { looked = true; return () => true; } }, new AbortController().signal);
  expect(blocked?.block).toBe(true); expect(looked).toBe(false);
  const revoked = await guardTool("write", { path: "extensions/file.ts", content: "new" }, root, { classify: async () => { throw new Error("should not classify"); }, approve: async () => true, scope: async () => () => false }, new AbortController().signal);
  expect(revoked?.reason).toContain("revoked");
});

test("bounded parent memory marked lower trust with namespaced source IDs", () => {
  const base: ReviewContext = { version: 1, sessionId: "child", leafId: null, memoryStatus: "available", memory: [], recent: [{ id: "task", role: "user", text: "child task" }], evidence: [], coverageId: null, truncated: false };
  const parent: ReviewContext = { ...base, sessionId: "parent", recent: [{ id: "restriction", role: "user", text: "no deployment" }], memory: [{ id: "m", kind: "observation", text: "Implement code", sourceIds: ["restriction"], sourceStatus: "complete" }] };
  const result = mergeParentContext(base, parent);
  expect(result.recent[0].id).toBe("parent:parent:restriction");
  expect(result.recent[0].text).toContain("not authorization");
  expect(result.memory[0].sourceIds).toEqual(["parent:parent:restriction"]);
  expect(result.recent.at(-1)?.text).toBe("child task");
  expect(base.recent).toHaveLength(1);
  expect(Buffer.byteLength(JSON.stringify(result))).toBeLessThanOrEqual(12288);
});
