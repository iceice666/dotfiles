import { expect, test } from "bun:test";
import { realpathSync } from "node:fs";
import { registerTodo } from "../index";
import { VerificationGate, type Backend, type RunResult } from "../verification";

const cwd = realpathSync(process.cwd());
const result = (): RunResult => ({ exitCode: 0, signal: null, timedOut: false, aborted: false, overflow: false, output: "tests passed" });
const declaration = { action: "add", text: "Verify feature", checks: [{ name: "tests", command: "bun test" }] };
function setup(options: { approve?: (...args: any[]) => Promise<boolean>; backend?: Backend } = {}) {
  const entries: any[] = [];
  const handlers = new Map<string, Function>();
  const commands = new Map<string, any>();
  const messages: any[] = [];
  const approvals: any[] = [];
  let tool: any;
  const gate = new VerificationGate(options.backend ?? { fingerprint: async () => "one", run: async () => result() });
  const ctx: any = { cwd, hasUI: false, mode: "print", sessionManager: { getBranch: () => entries }, hasPendingMessages: () => false };
  registerTodo({
    on: (name: string, fn: Function) => handlers.set(name, fn),
    registerTool: (value: any) => { tool = value; }, registerCommand: (name: string, value: any) => commands.set(name, value),
    appendEntry: (customType: string, data: any) => entries.push({ type: "custom", customType, data: structuredClone(data) }),
    getActiveTools: () => ["todo"], sendMessage: (...args: any[]) => messages.push(args),
  } as any, { gate, approve: async (...args: any[]) => { approvals.push(args); return options.approve ? options.approve(...args) : true; } });
  return { entries, ctx, approvals, messages, gate,
    call: (params: any, signal?: AbortSignal) => tool.execute("test", params, signal, undefined, ctx),
    event: (name: string, event = {}) => handlers.get(name)?.(event, ctx),
  };
}

test("explicit declaration approval binds canonical cwd and never approves ordinary tasks", async () => {
  const s = setup();
  await s.event("session_start");
  await s.call({ action: "add", text: "ordinary" });
  expect(s.approvals).toEqual([]);
  const added = await s.call(declaration);
  expect(s.approvals).toHaveLength(1);
  expect(s.approvals[0][1]).toEqual({ toolName: "todo", input: { action: "add", items: [{ text: declaration.text, checks: declaration.checks }] }, cwd });
  expect(added.details.state.todos[1].declaration.cwd).toBe(cwd);
  await expect(s.call({ action: "update", id: 2, status: "completed" })).rejects.toThrow(/verify/);
  const verified = await s.call({ action: "verify", id: 2 });
  expect(verified.details.evidence.runs[0].result.output).toBe("tests passed");
  await s.call({ action: "update", id: 2, status: "completed" });
  expect(s.entries.some(entry => entry.customType === "local-todo-verification-v1")).toBe(true);
});

test("denied or cancelled declarations never add a partial batch", async () => {
  const s = setup({ approve: async () => false });
  await s.event("session_start");
  await expect(s.call({ action: "add", items: [{ text: "ordinary" }, { text: declaration.text, checks: declaration.checks }] })).rejects.toThrow(/human approval/);
  expect(s.entries).toEqual([]);
  expect((await s.call({ action: "list" })).details.state.nextId).toBe(1);
  const controller = new AbortController();
  const cancelled = setup({ approve: async () => { controller.abort(); return true; } });
  await expect(cancelled.call(declaration, controller.signal)).rejects.toThrow();
  expect(cancelled.entries).toEqual([]);
});

test("compaction preserves current live evidence; restart/tree reopen dependent closure", async () => {
  const s = setup();
  await s.event("session_start");
  await s.call(declaration);
  await s.call({ action: "verify", id: 1 });
  await s.call({ action: "update", id: 1, status: "completed" });
  await s.call({ action: "add", text: "dependent", blockedBy: [1], status: "completed" });
  await s.event("session_compact");
  expect((await s.call({ action: "list" })).details.state.todos.map((t: any) => t.status)).toEqual(["completed", "completed"]);
  expect(s.messages.at(-1)[1]).toEqual({ triggerTurn: false });
  await s.event("session_tree");
  expect((await s.call({ action: "list" })).details.state.todos.map((t: any) => t.status)).toEqual(["pending", "pending"]);
  await s.call({ action: "verify", id: 1 });
  await s.call({ action: "update", id: 1, status: "completed" });
  await s.event("session_start");
  expect((await s.call({ action: "list" })).details.state.todos[0].status).toBe("pending");
});

test("legacy missing approval and fork into another cwd stay blocked", async () => {
  const s = setup();
  await s.call(declaration);
  delete s.entries[0].data.todos[0].declaration;
  await s.event("session_start");
  await expect(s.call({ action: "verify", id: 1 })).rejects.toThrow(/approval/);
  await expect(s.call({ action: "clear" })).rejects.toThrow(/unverified/);
  const other = setup();
  await other.call(declaration);
  other.ctx.cwd = "/";
  await other.event("session_start");
  await expect(other.call({ action: "verify", id: 1 })).rejects.toThrow(/approval/);
});

test("successful process followed by changed current fingerprint reports failure", async () => {
  let fingerprints = 0;
  const s = setup({ backend: { fingerprint: async () => ++fingerprints <= 2 ? "one" : "two", run: async () => result() } });
  await s.call(declaration);
  await expect(s.call({ action: "verify", id: 1 })).rejects.toThrow(/changed after verification/);
  await expect(s.call({ action: "update", id: 1, status: "completed" })).rejects.toThrow(/verify/);
});

test("queued parallel verify/completion serialize and shutdown aborts an active run", async () => {
  let entered!: () => void;
  const running = new Promise<void>(resolve => { entered = resolve; });
  const s = setup({ backend: { fingerprint: async () => "one", run: async (_command, _cwd, signal) => {
    entered();
    await new Promise(resolve => signal!.addEventListener("abort", resolve, { once: true }));
    return { ...result(), aborted: true };
  } } });
  await s.call(declaration);
  const verification = s.call({ action: "verify", id: 1 }).then(() => false, () => true);
  const completion = s.call({ action: "update", id: 1, status: "completed" }).then(() => false, () => true);
  await running;
  const stopping = s.event("session_shutdown");
  expect(await Promise.all([verification, completion])).toEqual([true, true]);
  await stopping;
  expect(s.gate.details(1)).toBeUndefined();
});

for (const hook of ["agent_end", "session_compact"] as const) {
  for (const transition of ["session_shutdown", "session_tree"] as const) {
    test(`${hook} cancellation on ${transition} cannot persist stale state or follow-ups`, async () => {
      let pause = false;
      let entered!: () => void;
      const pending = new Promise<void>(resolve => { entered = resolve; });
      const s = setup({ backend: { fingerprint: async (_cwd, signal) => {
        if (pause) {
          entered();
          await new Promise<void>(resolve => {
            if (signal?.aborted) resolve();
            else signal?.addEventListener("abort", () => resolve(), { once: true });
          });
        }
        return "one";
      }, run: async () => result() } });
      await s.call(declaration);
      await s.call({ action: "verify", id: 1 });
      await s.call({ action: "update", id: 1, status: "completed" });
      await s.call({ action: "add", text: "unfinished" });
      const entries = structuredClone(s.entries);
      pause = true;
      const ending = s.event(hook, { messages: [{ role: "assistant", stopReason: "stop" }] });
      await pending;
      const stopping = s.event(transition);
      await Promise.all([ending, stopping]);
      expect(s.entries).toEqual(entries);
      expect(s.messages).toEqual([]);
    });
  }
}

test("cancelled completion fingerprint cannot persist invalidation", async () => {
  let pause = false;
  let entered!: () => void;
  const pending = new Promise<void>(resolve => { entered = resolve; });
  const s = setup({ backend: { fingerprint: async (_cwd, signal) => {
    if (pause) {
      entered();
      await new Promise<void>(resolve => signal!.addEventListener("abort", () => resolve(), { once: true }));
    }
    return "one";
  }, run: async () => result() } });
  await s.call(declaration);
  await s.call({ action: "verify", id: 1 });
  await s.call({ action: "update", id: 1, status: "completed" });
  const entries = structuredClone(s.entries);
  const controller = new AbortController();
  pause = true;
  const listed = s.call({ action: "list" }, controller.signal).then(() => false, () => true);
  await pending;
  controller.abort();
  expect(await listed).toBe(true);
  expect(s.entries).toEqual(entries);
});
