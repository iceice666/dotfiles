import { expect, test } from "bun:test";
import extension from "../index.ts";
import { conversationSnapshot } from "../context.ts";

const tick = () => new Promise(resolve => setTimeout(resolve, 0));
function deferred() {
  let resolve!: (value: any) => void, reject!: (error: unknown) => void;
  const promise = new Promise<any>((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
const answer = (text = "side answer") => ({ stopReason: "stop", content: [{ type: "text", text }] });
function setup(busy = false, mode = "tui") {
  let command: any;
  const handlers = new Map<string, (...args: any[]) => any>();
  const renderers = new Map<string, any>();
  const calls: any[] = [], pending: ReturnType<typeof deferred>[] = [];
  const entries: any[] = [{ type: "message", id: "main", parentId: null, timestamp: "2026-01-01T00:00:00.000Z", message: { role: "user", content: "main task snapshot", timestamp: 0 } }];
  const appended: any[] = [], notifications: any[] = [], statuses: any[] = [];
  const mutations: string[] = [];
  const forbidden = (name: string) => () => { mutations.push(name); throw new Error(`Unexpected main mutation: ${name}`); };
  const pi: any = {
    on: (event: string, handler: any) => handlers.set(event, handler),
    registerCommand: (name: string, definition: any) => { expect(name).toBe("btw"); command = definition; },
    registerEntryRenderer: (name: string, renderer: any) => renderers.set(name, renderer),
    appendEntry: (customType: string, data: any) => {
      appended.push({ customType, data });
      entries.push({ type: "custom", customType, data, id: `custom-${entries.length}`, parentId: entries.at(-1).id, timestamp: "2026-01-01T00:00:01.000Z" });
    },
    sendMessage: forbidden("sendMessage"), sendUserMessage: forbidden("sendUserMessage"),
    setModel: forbidden("setModel"), setThinkingLevel: forbidden("setThinkingLevel"),
    setActiveTools: forbidden("setActiveTools"), exec: forbidden("exec"),
  };
  const ctx: any = {
    mode, hasUI: mode !== "print", isIdle: () => !busy,
    model: { provider: "test-provider", id: "test-model", maxTokens: 8192 },
    modelRegistry: { complete: (...args: any[]) => {
      calls.push(args); const request = deferred(); pending.push(request); return request.promise;
    } },
    sessionManager: { getBranch: () => entries, buildContextEntries: () => entries },
    ui: { notify: (...args: any[]) => notifications.push(args), setStatus: (...args: any[]) => statuses.push(args) },
    abort: forbidden("abort"), waitForIdle: forbidden("waitForIdle"),
    newSession: forbidden("newSession"), fork: forbidden("fork"), navigateTree: forbidden("navigateTree"),
  };
  extension(pi);
  return { ctx, calls, pending, entries, appended, notifications, statuses, mutations, renderers,
    call: (question: string) => command.handler(question, ctx),
    event: (name: string) => handlers.get(name)?.({}, ctx),
  };
}

for (const busy of [false, true]) test(`side request returns immediately with main agent ${busy ? "busy" : "idle"}`, async () => {
  const s = setup(busy);
  await s.call("  explain current task  ");
  expect(s.calls).toHaveLength(1);
  expect(s.appended).toHaveLength(0);
  const [model, context, options] = s.calls[0];
  expect(model).toBe(s.ctx.model);
  expect(context.systemPrompt).toContain("no tools");
  expect(context.tools).toBeUndefined();
  expect(context.messages).toHaveLength(2);
  expect(context.messages[0].content).toContain("main task snapshot");
  expect(context.messages[1].content).toBe("explain current task");
  expect(context.messages.every((message: any) => message.role === "user")).toBe(true);
  expect(options).toMatchObject({ maxTokens: 4096, maxRetries: 0, cacheRetention: "none", timeoutMs: 120000 });
  expect(options.signal).toBeInstanceOf(AbortSignal);
  expect(options.sessionId).toBeTruthy();
  s.entries[0].message.content = "changed after snapshot";
  expect(context.messages[0].content).not.toContain("changed after snapshot");
  s.pending[0].resolve(answer()); await tick();
  expect(s.appended).toEqual([{ customType: "btw-answer", data: { question: "explain current task", answer: "side answer", model: "test-provider/test-model" } }]);
  expect(s.renderers.has("btw-answer")).toBe(true);
  expect(conversationSnapshot(s.entries)).not.toContain("side answer");
  expect(conversationSnapshot(s.entries)).not.toContain("explain current task");
  expect(s.statuses.at(-1)).toEqual(["btw", undefined]);
  expect(s.mutations).toEqual([]);
});

test("overlapping calls do not start another request; completed calls use independent IDs", async () => {
  const s = setup();
  await s.call("first"); await s.call("second");
  expect(s.calls).toHaveLength(1);
  expect(s.notifications.at(-1)[0]).toContain("already running");
  s.pending[0].resolve(answer()); await tick();
  await s.call("third");
  expect(s.calls).toHaveLength(2);
  expect(s.calls[1][2].sessionId).not.toBe(s.calls[0][2].sessionId);
  s.pending[1].resolve(answer()); await tick();
  expect(s.mutations).toEqual([]);
});

for (const event of ["cancel", "session_shutdown", "session_before_tree"]) test(`${event} aborts only side request and suppresses late completion`, async () => {
  const s = setup(true);
  await s.call("old question");
  if (event === "cancel") await s.call("cancel"); else await s.event(event);
  expect(s.calls[0][2].signal.aborted).toBe(true);
  await s.call("new question");
  const statusCount = s.statuses.length;
  s.pending[0].resolve(answer("STALE ANSWER")); await tick();
  expect(s.appended).toHaveLength(0);
  expect(s.statuses).toHaveLength(statusCount);
  s.pending[1].resolve(answer("new answer")); await tick();
  expect(s.appended[0].data.answer).toBe("new answer");
  expect(JSON.stringify(s.notifications)).not.toContain("failed");
  expect(s.mutations).toEqual([]);
});

test("cancelled request late rejection is suppressed", async () => {
  const s = setup(); await s.call("question"); await s.call("cancel");
  s.pending[0].reject(new Error("PRIVATE PROVIDER ERROR")); await tick();
  expect(s.appended).toHaveLength(0);
  expect(JSON.stringify(s.notifications)).not.toContain("PRIVATE");
  expect(s.notifications).toHaveLength(1);
});

test("provider failure is redacted and releases slot", async () => {
  const s = setup(); await s.call("question");
  s.pending[0].reject(new Error("PRIVATE token=secret request body")); await tick();
  expect(s.notifications.at(-1)[1]).toBe("error");
  expect(s.notifications.at(-1)[0]).toContain("Provider details withheld");
  expect(JSON.stringify(s.notifications)).not.toContain("PRIVATE");
  expect(s.appended).toHaveLength(0);
  await s.call("retry"); s.pending[1].resolve(answer()); await tick();
  expect(s.appended).toHaveLength(1);
});

for (const response of [
  { stopReason: "error", content: [{ type: "text", text: "PRIVATE FAILURE" }] },
  { stopReason: "stop", content: [{ type: "thinking", thinking: "PRIVATE THOUGHT" }] },
  { stopReason: "stop", content: [{ type: "text", text: "unsafe" }, { type: "toolCall", name: "bash", arguments: {} }] },
]) test("invalid model response is not stored or executed", async () => {
  const s = setup(); await s.call("question"); s.pending[0].resolve(response); await tick();
  expect(s.appended).toHaveLength(0);
  expect(s.notifications.at(-1)[1]).toBe("error");
  expect(JSON.stringify(s.notifications)).not.toContain("PRIVATE");
  expect(s.mutations).toEqual([]);
});

test("usage, missing model, headless and oversized requests make no model calls", async () => {
  const s = setup(); await s.call(""); await s.call("cancel"); await s.call("x".repeat(8001));
  s.ctx.model = undefined; await s.call("question");
  expect(s.calls).toHaveLength(0);
  const headless = setup(false, "print"); await headless.call("question");
  expect(headless.calls).toHaveLength(0);
  expect(headless.notifications).toHaveLength(0);
});

test("RPC gets readable answer notification and answer size is bounded", async () => {
  const s = setup(false, "rpc"); s.ctx.model.maxTokens = 1024;
  await s.call("question"); expect(s.calls[0][2].maxTokens).toBe(1024);
  s.pending[0].resolve(answer("x".repeat(24001))); await tick();
  expect(s.appended[0].data.answer).toBe("x".repeat(24000) + "\n\n[Answer truncated.]");
  expect(s.notifications.at(-1)[0]).toContain("BTW: question");
});
