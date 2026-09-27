import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import extension from "../index.ts";
import { attestRuntime, managedRoot } from "../boundary.ts";
import { guardTool } from "../gate.ts";
import { askHumanDecision } from "../../ask-question/service.ts";

const root = `/nix/store/${"a".repeat(32)}-pi-extensions`;
const managedTools = [
  { name: "read", sourceInfo: { path: `${root}/execution-policy/bootstrap.ts` } },
  { name: "bash", sourceInfo: { path: `${root}/execution-policy/bootstrap.ts` } },
  { name: "background_task", sourceInfo: { path: `${root}/background-task` } },
  { name: "grep", sourceInfo: { path: "<builtin:grep>" } },
];
const ready = { ok: true };

describe("runtime attestation", () => {
  test("only the content-addressed managed tree counts as managed", () => {
    expect(managedRoot(`${root}/auto-mode/index.ts`)).toBe(root);
    for (const path of ["/Users/me/.pi/agent/extensions/auto-mode/index.ts", "/nix/store/short-pi-extensions/auto-mode/index.ts", `/nix/store/${"a".repeat(32)}-other/auto-mode/index.ts`]) {
      expect(managedRoot(path)).toBeUndefined();
    }
  });
  test("confined only with managed root, ready sandbox, policy-owned read/bash and a managed called tool", () => {
    expect(attestRuntime({ root, tools: managedTools, toolName: "background_task", boundary: ready }).confined).toBe(true);
    expect(attestRuntime({ root: undefined, tools: managedTools, toolName: "bash", boundary: ready }).confined).toBe(false);
    const missing = attestRuntime({ root, tools: managedTools, toolName: "bash", boundary: { ok: false, reason: "toolchain missing" } });
    expect(missing).toEqual({ confined: false, reason: "toolchain missing" });
    const foreignBash = managedTools.map(tool => tool.name === "bash" ? { ...tool, sourceInfo: { path: "<builtin:bash>" } } : tool);
    expect(attestRuntime({ root, tools: foreignBash, toolName: "read", boundary: ready }).confined).toBe(false);
    expect(attestRuntime({ root, tools: managedTools, toolName: "grep", boundary: ready }).confined).toBe(false);
    expect(attestRuntime({ root, tools: managedTools, toolName: "unregistered", boundary: ready }).confined).toBe(false);
    const escaped = [...managedTools, { name: "x", sourceInfo: { path: `${root}/../elsewhere/x.ts` } }];
    expect(attestRuntime({ root, tools: escaped, toolName: "x", boundary: ready }).confined).toBe(false);
  });
});

describe("gate escalation", () => {
  const cwd = process.cwd();
  const signal = () => new AbortController().signal;
  test("escalation never lets a classifier allow execute; approval carries the refusal", async () => {
    for (const approved of [true, false]) {
      const reasons: string[] = [];
      const result = await guardTool("bash", { command: "true" }, cwd, {
        classify: async () => ({ decision: "allow", reason: "routine" }),
        approve: async (_action, reason) => { reasons.push(reason); return approved; },
        escalate: () => "earlier refusal",
      }, signal());
      expect(result === undefined).toBe(approved);
      if (!approved) expect(result?.denied).toBe(true);
      expect(reasons).toEqual(["earlier refusal Reviewer: routine"]);
    }
  });
  test("classifier deny still wins; local-ask actions stay away from the classifier; coordination can escalate", async () => {
    let asked = false;
    expect((await guardTool("bash", { command: "true" }, cwd, { classify: async () => ({ decision: "deny", reason: "bypass" }), approve: async () => { asked = true; return true; }, escalate: () => "x" }, signal()))?.denied).toBe(true);
    expect(asked).toBe(false);
    let classified = false;
    expect(await guardTool("bash", { command: "cat ~/.ssh/config" }, cwd, { classify: async () => { classified = true; return { decision: "allow", reason: "" }; }, approve: async () => true, escalate: () => "x" }, signal())).toBeUndefined();
    expect(classified).toBe(false);
    expect((await guardTool("agent_send", { to: "worker", message: "do it" }, cwd, { classify: async () => ({ decision: "allow", reason: "ok" }), approve: async () => false, escalate: () => "x" }, signal()))?.block).toBe(true);
  });
  test("procedural blocks are not recorded as refusals", async () => {
    const result = await guardTool("bash", { command: "x".repeat(40000) }, cwd, { classify: async () => ({ decision: "allow", reason: "" }), approve: async () => true }, signal());
    expect(result?.block).toBe(true); expect(result?.denied).toBeUndefined();
    expect((await guardTool("read", { path: ".env" }, cwd, { classify: async () => ({ decision: "allow", reason: "" }), approve: async () => true }, signal()))?.denied).toBe(true);
  });
});

let workerEnv: string | undefined;
beforeEach(() => { workerEnv = process.env.PI_TEAM_AGENT; delete process.env.PI_TEAM_AGENT; });
afterEach(() => { if (workerEnv === undefined) delete process.env.PI_TEAM_AGENT; else process.env.PI_TEAM_AGENT = workerEnv; });

function setup(attestation = { confined: true, reason: "" }, verdict = "allow") {
  const handlers = new Map<string, any>(), commands = new Map<string, any>();
  const calls: any[] = [], notes: any[] = [], statuses = new Map<string, string>(), views: any[] = [];
  const ctx: any = { cwd: process.cwd(), mode: "tui", hasUI: false,
    sessionManager: { getSessionId: () => "s", getBranch: () => [], getLeafId: () => null },
    model: { provider: "test", id: "test", maxTokens: 2048 },
    modelRegistry: { complete: async (...args: any[]) => { calls.push(args); return { stopReason: "stop", content: [{ type: "text", text: `{"decision":"${verdict}","reason":"model"}` }] }; } },
    ui: { notify: (...args: any[]) => notes.push(args), setStatus: (key: string, value: string) => statuses.set(key, value),
      custom: (factory: any) => new Promise(resolve => views.push(factory({ requestRender() {}, terminal: { rows: 24, columns: 100 } }, { fg: (_: string, s: string) => s }, {}, resolve))) } };
  extension({ on: (n: string, h: any) => handlers.set(n, h), registerCommand: (n: string, c: any) => commands.set(n, c), getAllTools: () => [] } as any, { attest: () => attestation });
  const event = (n: string, e: any = {}) => handlers.get(n)?.(e, ctx);
  return { ctx, calls, notes, statuses, views, event, command: (name: string, args: string) => commands.get(name).handler(args, ctx),
    payload: (i = -1) => JSON.parse(calls.at(i)[1].messages[0].content[0].text) };
}
const bash = { toolName: "bash", input: { command: "git status" } };
const background = { toolName: "background_task", input: { action: "start", command: "cat deploy.md" } };

describe("extension", () => {
  test("unconfined runtime blocks execution even with /auto off or YOLO, keeps coordination, refuses YOLO", async () => {
    const s = setup({ confined: false, reason: "toolchain missing" });
    s.ctx.hasUI = true;
    await s.event("session_start");
    expect(s.statuses.get("auto-mode")).toBe("auto:UNCONFINED");
    expect(s.notes.some(([text, level]) => level === "error" && text.includes("toolchain missing"))).toBe(true);
    const blocked = await s.event("tool_call", background);
    expect(blocked).toMatchObject({ block: true, terminate: true });
    expect(blocked.reason).toContain("security boundary");
    expect(await s.event("tool_call", { toolName: "ask_user_question", input: { questions: [] } })).toBeUndefined();
    expect(await s.event("tool_call", { toolName: "background_task", input: { action: "stop", id: "x" } })).toBeUndefined();
    await s.command("yolo", "on");
    expect((await s.event("tool_call", bash))?.block).toBe(true);
    expect(s.calls).toHaveLength(0);
  });

  test("sandbox refusal forces human approval for substitute execution until the next human turn", async () => {
    const s = setup();
    await s.event("input", { source: "interactive", text: "deploy per deploy.md" });
    await s.event("tool_result", { toolName: "read", isError: true, content: [{ type: "text", text: "Restricted execution unavailable: the pinned /nix/store toolchain is missing." }] });
    const held = await s.event("tool_call", background);
    expect(held?.block).toBe(true);
    expect(held.reason).toContain("No explicit approval");
    expect(s.payload().boundary.recentDenials[0]).toMatchObject({ toolName: "read", source: "sandbox" });
    // Ordinary file errors and agent coordination with the human do not trip or hit the breaker.
    expect(await s.event("tool_call", { toolName: "agent_ask", input: { to: "user", question: "?" } })).toBeUndefined();
    await s.event("input", { source: "interactive", text: "ok, continue" });
    await s.event("tool_result", { toolName: "read", isError: true, content: [{ type: "text", text: "Restricted file operation failed: ENOENT" }] });
    expect(await s.event("tool_call", background)).toBeUndefined();
    expect(s.payload().boundary).toBeUndefined();
  });

  test("an Auto Mode denial also arms the breaker; non-human input does not reset it", async () => {
    const s = setup(undefined, "deny");
    expect((await s.event("tool_call", bash))?.block).toBe(true);
    s.ctx.modelRegistry.complete = async (...args: any[]) => { s.calls.push(args); return { stopReason: "stop", content: [{ type: "text", text: '{"decision":"allow","reason":"model"}' }] }; };
    await s.event("input", { source: "rpc", text: "continue" });
    expect((await s.event("tool_call", background))?.block).toBe(true);
    expect(s.payload().boundary.recentDenials[0].source).toBe("auto-mode");
  });

  test("live parent TUI answers become trusted task decisions until the next input", async () => {
    const s = setup();
    s.ctx.hasUI = true;
    await s.event("session_start");
    await s.event("input", { source: "interactive", text: "deploy pirc" });
    const asking = askHumanDecision(s.ctx, { questions: [{ question: "Tools fail. What now?", options: [{ label: "Investigate first", description: "diagnose the environment" }, { label: "Deploy anyway" }] }] });
    await new Promise(resolve => setTimeout(resolve, 0));
    s.views[0].handleInput("\r"); s.views[0].handleInput("\r");
    expect((await asking).status).toBe("answered");
    await s.event("tool_call", bash);
    expect(s.payload().task).toEqual({ text: "deploy pirc", human: true,
      decisions: [{ question: "Tools fail. What now?", selected: ["Investigate first — diagnose the environment"] }] });
    await s.event("input", { source: "interactive", text: "next" });
    await s.event("tool_call", bash);
    expect(s.payload().task).toEqual({ text: "next", human: true });
    await s.event("session_shutdown");
  });

  test("RPC answers and worker processes never publish decisions", async () => {
    const s = setup();
    await s.event("session_start");
    const rpc = { ...s.ctx, mode: "rpc", hasUI: true, ui: { ...s.ctx.ui, select: async (_t: string, rows: string[]) => rows[0] } };
    expect((await askHumanDecision(rpc, { questions: [{ question: "Deploy?", options: [{ label: "Yes" }] }] })).status).toBe("answered");
    await s.event("tool_call", bash);
    expect(s.payload().task.decisions).toBeUndefined();
    await s.event("session_shutdown");
  });
});
