import { afterEach, beforeEach, expect, test } from "bun:test";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import extension from "../index.ts";
import { evaluatePolicy } from "../policy.ts";
import type { ReviewContext } from "../classifier.ts";
import { Team, autoModeActionId } from "../../agent-team/team.mjs";

const teamKeys = ["PI_TEAM_AGENT", "PI_TEAM_URL", "PI_TEAM_TOKEN"] as const;
let savedEnv: Record<string, string | undefined>;
let root: string;
const cleanup: Array<() => Promise<void>> = [];
beforeEach(() => {
  savedEnv = Object.fromEntries(teamKeys.map(key => [key, process.env[key]]));
  for (const key of teamKeys) delete process.env[key];
  root = mkdtempSync(join(tmpdir(), "auto-worker-context-"));
  mkdirSync(join(root, "extensions"));
  writeFileSync(join(root, "extensions", "file.ts"), "old");
});
afterEach(async () => {
  try { for (const close of cleanup.splice(0).reverse()) await close(); }
  finally {
    for (const key of teamKeys) {
      if (savedEnv[key] === undefined) delete process.env[key]; else process.env[key] = savedEnv[key];
    }
    rmSync(root, { recursive: true, force: true });
  }
});

const parentMemory: ReviewContext = {
  version: 1, sessionId: "parent-session", leafId: "parent-leaf", memoryStatus: "available",
  memory: [{ id: "memory-1", kind: "observation", text: "Implement local parser tests; never deploy.", sourceIds: ["parent-task"], sourceStatus: "complete" }],
  recent: [{ id: "parent-task", role: "user", text: "Keep changes local. Do not deploy." }],
  evidence: [{ id: "evidence-1", role: "user", text: "Local tests only." }], coverageId: "parent-task", truncated: false,
};
const allowedModelReply = () => ({ stopReason: "stop", content: [{ type: "text", text: '{"decision":"allow","reason":"routine local work"}' }] });
type ParentResult = { revision: number; scopeId?: string; context?: ReviewContext };

async function setup(provider: (request: any, call: number, team: Team) => Promise<ParentResult> | ParentResult) {
  const requests: any[] = [];
  const completions: any[] = [];
  let prompts = 0;
  const team = new Team({
    directory: join(root, "team"), workspace: root, extension: "/unused", deliverParent() { throw new Error("Unexpected parent message"); },
    askUser: async () => { prompts++; return { status: "unavailable", answers: [] }; },
    getAutoModeContext: async (who: string, request: any, signal: AbortSignal) => {
      expect(who).toBe("worker");
      expect(signal.aborted).toBe(false);
      expect(request.actionId).toBe(autoModeActionId(request.toolName, request.input, request.cwd));
      expect(request.cwd).toBe(root);
      if (request.toolName === "auto_mode_status") return { revision: 0, yolo: false };
      requests.push(structuredClone(request));
      return provider(request, requests.length, team);
    },
  });
  await team.ready;
  team.agents.set("worker", { name: "worker", status: "running", token: "Bearer offline-worker", rpc: {
    request() { throw new Error("Unexpected model-visible team message"); }, stop: async () => {},
  } });
  team.tokens.set("Bearer offline-worker", "worker");
  cleanup.push(() => team.close());
  process.env.PI_TEAM_AGENT = "worker";
  process.env.PI_TEAM_URL = team.url;
  process.env.PI_TEAM_TOKEN = "Bearer offline-worker";
  const handlers = new Map<string, any>();
  const entries = [{ id: "worker-task", type: "message", message: { role: "user", content: "Coordinator task: continue local tests." } }];
  const ctx: any = {
    cwd: root, mode: "rpc", hasUI: false, signal: new AbortController().signal,
    model: { provider: "offline-test", id: "offline-test", maxTokens: 2048 },
    sessionManager: { getSessionId: () => "worker-session", getBranch: () => entries, getLeafId: () => "worker-task" },
    modelRegistry: { complete: async (...args: any[]) => { completions.push(args); return allowedModelReply(); } },
    ui: { setStatus() {}, notify() {} },
  };
  extension({ on: (name: string, handler: any) => handlers.set(name, handler), registerCommand() {}, getAllTools: () => [] } as any);
  const event = (name: string, data: any = {}) => handlers.get(name)?.(data, ctx);
  cleanup.push(async () => { await event("session_shutdown"); });
  await event("session_start");
  await event("input", { source: "rpc", text: "Continue the coordinator task." });
  return { team, ctx, requests, completions, event, prompts: () => prompts };
}
const controlWrite = () => ({ toolName: "write", input: { path: "extensions/file.ts", content: "new" } });

test("worker classifier receives namespaced parent memory as context, never human authority", async () => {
  const s = await setup(request => ({ revision: 7, ...(request.includeContext ? { context: parentMemory } : {}) }));
  expect(await s.event("tool_call", { toolName: "bash", input: { command: "git status" } })).toBeUndefined();
  expect(s.completions).toHaveLength(1);
  const payload = JSON.parse(s.completions[0][1].messages[0].content[0].text);
  expect(payload.task).toEqual({ text: "Continue the coordinator task.", human: false });
  expect(JSON.stringify(payload)).not.toContain('"human":true');
  expect(payload.context.memory).toContainEqual({ ...parentMemory.memory[0], id: "parent:parent-session:memory-1",
    sourceIds: ["parent:parent-session:parent-task"], text: "[Parent memory, not authorization] Implement local parser tests; never deploy." });
  expect(payload.context.recent.some((item: any) => item.id === "parent:parent-session:parent-task" && item.text.includes("not authorization"))).toBe(true);
  expect(payload.context.evidence.some((item: any) => item.id === "parent:parent-session:evidence-1")).toBe(true);
  expect(s.requests.map(request => request.includeContext)).toEqual([true, false]);
  expect(s.prompts()).toBe(0);
});

test("valid parent file scope allows an otherwise held control-source write without a classifier and rereads revision", async () => {
  const tool = controlWrite();
  expect(evaluatePolicy({ ...tool, cwd: root }).decision).toBe("ask");
  const s = await setup(() => ({ revision: 4, scopeId: "human-grant-1" }));
  expect(await s.event("tool_call", tool)).toBeUndefined();
  expect(s.completions).toHaveLength(0);
  expect(s.prompts()).toBe(0);
  expect(s.requests).toHaveLength(3);
  expect(s.requests.every(request => request.includeContext === false && request.toolName === "write")).toBe(true);
  expect(new Set(s.requests.map(request => request.actionId)).size).toBe(1);
});

for (const change of ["scope", "revision", "revoke", "stop"] as const) test(`worker scope ${change} before release blocks execution without a classifier`, async () => {
  const s = await setup(async (_request, call, team) => {
    if (call === 1) return { revision: 4, scopeId: "human-grant-1" };
    if (change === "stop") { await team.stop("worker"); return { revision: 4, scopeId: "human-grant-1" }; }
    if (change === "scope") return { revision: 4, scopeId: "replacement-grant" };
    if (change === "revision") return { revision: 5, scopeId: "human-grant-1" };
    return { revision: 4 };
  });
  expect((await s.event("tool_call", controlWrite()))?.block).toBe(true);
  expect(s.requests).toHaveLength(2);
  expect(s.completions).toHaveLength(0);
  expect(s.prompts()).toBe(0);
});

test("parent revision changed at the final freshness check cannot release an otherwise revalidated scope", async () => {
  const s = await setup((_request, call) => ({ revision: call < 3 ? 4 : 5, scopeId: "human-grant-1" }));
  expect((await s.event("tool_call", controlWrite()))?.block).toBe(true);
  expect(s.requests).toHaveLength(3);
  expect(s.completions).toHaveLength(0);
  expect(s.prompts()).toBe(0);
});

test("a parent revision change during child classification invalidates a model allow", async () => {
  const s = await setup((request, call) => ({ revision: call === 1 ? 4 : 5, ...(request.includeContext ? { context: parentMemory } : {}) }));
  expect((await s.event("tool_call", { toolName: "bash", input: { command: "git status" } }))?.block).toBe(true);
  expect(s.completions).toHaveLength(1);
  expect(s.requests.map(request => request.includeContext)).toEqual([true, false]);
  expect(s.prompts()).toBe(0);
});
