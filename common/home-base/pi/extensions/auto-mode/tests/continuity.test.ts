import { afterEach, beforeEach, expect, test } from "bun:test";
let workerEnv: string | undefined;
beforeEach(() => { workerEnv = process.env.PI_TEAM_AGENT; delete process.env.PI_TEAM_AGENT; });
afterEach(() => { if (workerEnv === undefined) delete process.env.PI_TEAM_AGENT; else process.env.PI_TEAM_AGENT = workerEnv; });
import extension from "../index.ts";
import { guardTool } from "../gate.ts";

function setup() {
  const handlers = new Map<string, any>();
  const calls: any[] = [];
  let sessionId = "one";
  let entries: any[] = [{ id: "task", type: "message", message: { role: "user", content: "Implement sandbox. Never deploy." } }];
  const ctx: any = { cwd: process.cwd(), mode: "print", hasUI: false,
    model: { provider: "test", id: "test", maxTokens: 2048 },
    sessionManager: { getSessionId: () => sessionId, getBranch: () => entries, getLeafId: () => entries.at(-1)?.id },
    modelRegistry: { complete: async (...args: any[]) => { calls.push(args); return { stopReason: "stop", content: [{ type: "text", text: '{"decision":"allow","reason":"routine"}' }] }; } },
    ui: { notify() {}, setStatus() {} },
  };
  extension({ on: (n: string, h: any) => handlers.set(n, h), registerCommand() {} } as any);
  return { ctx, calls, event: (n: string, data: any = {}) => handlers.get(n)?.(data, ctx),
    setEntries: (value: any[]) => { entries = value; }, setSession: (id: string) => { sessionId = id; } };
}
const tool = { toolName: "bash", input: { command: "git status" } };

test("continue carries earlier branch task and newest restriction in separate context", async () => {
  const s = setup();
  s.setEntries([{ id: "task", type: "message", message: { role: "user", content: "Implement sandbox. Never deploy." } },
    { id: "continue", type: "message", message: { role: "user", content: "繼續" } }]);
  await s.event("input", { source: "rpc", text: "繼續" });
  expect(await s.event("tool_call", tool)).toBeUndefined();
  const payload = JSON.parse(s.calls[0][1].messages[0].content[0].text);
  expect(payload.task).toEqual({ text: "繼續", human: false });
  expect(payload.context.recent.map((e: any) => e.text)).toEqual(["Implement sandbox. Never deploy.", "繼續"]);
});

for (const change of ["session", "branch", "input", "tree"]) test(`${change} change invalidates a pending model allow`, async () => {
  const s = setup();
  s.ctx.modelRegistry.complete = async () => {
    if (change === "session") s.setSession("two");
    if (change === "branch") s.setEntries([{ id: "other", type: "message", message: { role: "user", content: "Different branch" } }]);
    if (change === "input") await s.event("input", { source: "rpc", text: "Stop now" });
    if (change === "tree") await s.event("session_tree");
    return { stopReason: "stop", content: [{ type: "text", text: '{"decision":"allow","reason":"routine"}' }] };
  };
  expect((await s.event("tool_call", tool))?.block).toBe(true);
});

test("background OM metadata append alone does not invalidate the same task", async () => {
  const s = setup();
  s.ctx.modelRegistry.complete = async () => {
    s.setEntries([...s.ctx.sessionManager.getBranch(), { id: "observation", type: "custom", customType: "om.observations.recorded", data: {} }]);
    return { stopReason: "stop", content: [{ type: "text", text: '{"decision":"allow","reason":"routine"}' }] };
  };
  expect(await s.event("tool_call", tool)).toBeUndefined();
});

test("stale snapshot cannot release a pending human-approved action either", async () => {
  let current = true;
  const result = await guardTool("edit", { path: "AGENTS.md", edits: [] }, process.cwd(), {
    classify: async () => ({ decision: "allow", reason: "routine" }),
    approve: async () => { current = false; return true; }, isCurrent: () => current,
  }, new AbortController().signal);
  expect(result?.block).toBe(true);
});
