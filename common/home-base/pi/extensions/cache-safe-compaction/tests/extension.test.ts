import { expect, test } from "bun:test";
import type { AssistantMessage } from "@earendil-works/pi-ai";
import extension, { activeTools, supportsCacheWarm, warmCompactedContext } from "../index.ts";

const usage = {
  input: 10,
  output: 1,
  cacheRead: 9,
  cacheWrite: 0,
  totalTokens: 20,
  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
};

function reply(overrides: Partial<AssistantMessage> = {}): AssistantMessage {
  return {
    role: "assistant",
    api: "openai-completions",
    provider: "cliproxyapi",
    model: "gpt-test",
    timestamp: 0,
    stopReason: "stop",
    content: [{ type: "text", text: "ok" }],
    usage,
    ...overrides,
  };
}

function setup(response: Promise<AssistantMessage> | AssistantMessage = reply()) {
  const handlers = new Map<string, (...args: any[]) => any>();
  const calls: any[] = [];
  const notifications: any[] = [];
  const statuses: any[] = [];
  const model: any = {
    provider: "cliproxyapi",
    id: "gpt-test",
    api: "openai-completions",
    maxTokens: 16384,
    compat: { supportsLongCacheRetention: true },
  };
  const pi: any = {
    on: (event: string, handler: any) => handlers.set(event, handler),
    getActiveTools: () => ["write", "read", "missing"],
    getAllTools: () => [
      { name: "read", description: "Read", parameters: { type: "object" }, sourceInfo: {} },
      { name: "write", description: "Write", parameters: { type: "object" }, sourceInfo: {} },
    ],
  };
  const ctx: any = {
    model,
    hasUI: true,
    getSystemPrompt: () => "stable system prompt",
    sessionManager: {
      getSessionId: () => "session-123",
      buildContextEntries: () => [
        {
          type: "compaction",
          id: "compact-1",
          parentId: null,
          timestamp: "1970-01-01T00:00:00.001Z",
          summary: "memory",
          firstKeptEntryId: "tail-1",
          tokensBefore: 1000,
        },
        {
          type: "message",
          id: "tail-1",
          parentId: "compact-1",
          timestamp: "1970-01-01T00:00:00.002Z",
          message: { role: "user", content: "retained tail", timestamp: 2 },
        },
      ],
    },
    modelRegistry: {
      complete: (...args: any[]) => {
        calls.push(args);
        return Promise.resolve(response);
      },
    },
    ui: {
      notify: (...args: any[]) => notifications.push(args),
      setStatus: (...args: any[]) => statuses.push(args),
    },
  };
  extension(pi);
  return { pi, ctx, handlers, calls, notifications, statuses };
}

function compactEvent(id = "compact-1"): any {
  return {
    type: "session_compact",
    compactionEntry: { id, type: "compaction" },
    fromExtension: true,
    reason: "threshold",
    willRetry: false,
  };
}

test("registers only post-compaction lifecycle hooks", () => {
  const s = setup();
  expect([...s.handlers.keys()].sort()).toEqual(["session_compact", "session_shutdown"]);
  expect(s.handlers.has("session_before_compact")).toBe(false);
});

test("warms the rebuilt compacted context with foreground cache identity", async () => {
  const s = setup();
  await s.handlers.get("session_compact")!(compactEvent(), s.ctx);

  expect(s.calls).toHaveLength(1);
  const [model, context, options] = s.calls[0];
  expect(model).toBe(s.ctx.model);
  expect(context.systemPrompt).toBe("stable system prompt");
  expect(context.messages).toEqual([
    {
      role: "user",
      content: [{
        type: "text",
        text: "The conversation history before this point was compacted into the following summary:\n\n<summary>\nmemory\n</summary>",
      }],
      timestamp: 1,
    },
    { role: "user", content: "retained tail", timestamp: 2 },
  ]);
  expect(context.tools.map((tool: any) => tool.name)).toEqual(["write", "read"]);
  expect(options).toMatchObject({
    sessionId: "session-123",
    cacheRetention: "long",
    toolChoice: "none",
    reasoningEffort: "minimal",
    maxTokens: 16,
    maxRetries: 0,
    timeoutMs: 30000,
  });
  expect(options.signal).toBeInstanceOf(AbortSignal);
  expect(s.notifications).toEqual([]);
  expect(s.statuses).toEqual([
    ["cache-safe-compaction", "warming compacted cache…"],
    ["cache-safe-compaction", undefined],
  ]);
});

test("preserves foreground active-tool order and ignores unknown names", () => {
  const s = setup();
  expect(activeTools(s.pi).map(tool => tool.name)).toEqual(["write", "read"]);
});

test("skips Anthropic and providers without explicit long-cache support", async () => {
  const s = setup();
  s.ctx.model = { ...s.ctx.model, api: "anthropic-messages", compat: { supportsLongCacheRetention: true } };
  expect(supportsCacheWarm(s.ctx.model)).toBe(false);
  await s.handlers.get("session_compact")!(compactEvent(), s.ctx);
  s.ctx.model = { ...s.ctx.model, api: "openai-responses", compat: { supportsLongCacheRetention: true } };
  expect(supportsCacheWarm(s.ctx.model)).toBe(false);
  await s.handlers.get("session_compact")!(compactEvent("compact-responses"), s.ctx);
  s.ctx.model = { ...s.ctx.model, api: "openai-completions", compat: {} };
  await s.handlers.get("session_compact")!(compactEvent("compact-2"), s.ctx);
  expect(s.calls).toHaveLength(0);
});

test("warms each compaction once", async () => {
  const s = setup();
  await s.handlers.get("session_compact")!(compactEvent(), s.ctx);
  await s.handlers.get("session_compact")!(compactEvent(), s.ctx);
  expect(s.calls).toHaveLength(1);
});

test("provider failures are redacted and do not fail compaction", async () => {
  const s = setup(Promise.reject(new Error("SECRET request payload")));
  await expect(s.handlers.get("session_compact")!(compactEvent(), s.ctx)).resolves.toBeUndefined();
  expect(s.notifications).toHaveLength(1);
  expect(s.notifications[0][1]).toBe("warning");
  expect(s.notifications[0][0]).toContain("Provider details withheld");
  expect(JSON.stringify(s.notifications)).not.toContain("SECRET");
  expect(s.statuses.at(-1)).toEqual(["cache-safe-compaction", undefined]);
});

test("shutdown aborts an in-flight warm request without a warning", async () => {
  const pending = new Promise<AssistantMessage>(() => {});
  const s = setup(pending);
  const warming = s.handlers.get("session_compact")!(compactEvent(), s.ctx);
  await Promise.resolve();
  s.handlers.get("session_shutdown")!({}, s.ctx);
  await warming;
  expect(s.calls[0][2].signal.aborted).toBe(true);
  expect(s.notifications).toEqual([]);
});

test("pre-aborted direct warm makes no provider request", async () => {
  const s = setup();
  const controller = new AbortController();
  controller.abort();
  expect(await warmCompactedContext(s.pi, s.ctx, { signal: controller.signal })).toBeUndefined();
  expect(s.calls).toHaveLength(0);
});
