import {
  convertToLlm,
  sessionEntryToContextMessages,
  type ExtensionAPI,
  type ExtensionContext,
  type SessionCompactEvent,
  type ToolInfo,
} from "@earendil-works/pi-coding-agent";
import type { Api, AssistantMessage, Context, Model, Tool } from "@earendil-works/pi-ai";

const STATUS_KEY = "cache-safe-compaction";
export const WARM_TIMEOUT_MS = 30_000;
export const WARM_MAX_TOKENS = 16;

type WarmOptions = {
  signal: AbortSignal;
  timeoutMs?: number;
};

type WarmResult = {
  response: AssistantMessage;
  context: Context;
};

/**
 * A warm request must use the same cache identity as the foreground session.
 * Limit this extension to explicitly opted-in OpenAI-compatible providers so
 * Anthropic cache writes and unrelated local providers are never enabled by
 * accident.
 */
export function supportsCacheWarm(model: Model<Api> | undefined): model is Model<Api> {
  if (!model) return false;
  if (model.api !== "openai-completions") return false;
  return (model.compat as { supportsLongCacheRetention?: boolean } | undefined)
    ?.supportsLongCacheRetention === true;
}

export function activeTools(pi: Pick<ExtensionAPI, "getActiveTools" | "getAllTools">): Tool[] {
  const byName = new Map<string, ToolInfo>(pi.getAllTools().map(tool => [tool.name, tool]));
  return pi.getActiveTools().flatMap(name => {
    const tool = byName.get(name);
    return tool ? [{ name: tool.name, description: tool.description, parameters: tool.parameters }] : [];
  });
}

function successfulWarm(response: AssistantMessage): boolean {
  return response.stopReason === "stop" || response.stopReason === "length";
}

export async function warmCompactedContext(
  pi: Pick<ExtensionAPI, "getActiveTools" | "getAllTools">,
  ctx: ExtensionContext,
  options: WarmOptions,
): Promise<WarmResult | undefined> {
  const model = ctx.model;
  if (!supportsCacheWarm(model) || options.signal.aborted) return;

  const agentMessages = ctx.sessionManager
    .buildContextEntries()
    .flatMap(sessionEntryToContextMessages);
  const context: Context = {
    systemPrompt: ctx.getSystemPrompt(),
    messages: convertToLlm(agentMessages),
    tools: activeTools(pi),
  };
  const timeoutMs = options.timeoutMs ?? WARM_TIMEOUT_MS;
  const controller = new AbortController();
  const abort = () => controller.abort();
  options.signal.addEventListener("abort", abort, { once: true });
  const timer = setTimeout(abort, timeoutMs);
  const aborted = new Promise<never>((_resolve, reject) => {
    controller.signal.addEventListener("abort", () => reject(new Error("Cache warm-up aborted")), { once: true });
  });

  try {
    const response = await Promise.race([
      ctx.modelRegistry.complete(model, context, {
        signal: controller.signal,
        sessionId: ctx.sessionManager.getSessionId(),
        cacheRetention: "long",
        toolChoice: "none",
        reasoningEffort: "minimal",
        maxTokens: Math.min(WARM_MAX_TOKENS, model.maxTokens),
        maxRetries: 0,
        timeoutMs,
      }),
      aborted,
    ]);
    if (!successfulWarm(response)) throw new Error("Cache warm-up returned an incomplete response");
    return { response, context };
  } finally {
    clearTimeout(timer);
    options.signal.removeEventListener("abort", abort);
  }
}

export default function cacheSafeCompaction(pi: ExtensionAPI) {
  const attempted = new Set<string>();
  let active: AbortController | undefined;

  const cancel = () => {
    active?.abort();
    active = undefined;
  };

  pi.on("session_shutdown", cancel);

  pi.on("session_compact", async (event: SessionCompactEvent, ctx: ExtensionContext) => {
    if (attempted.has(event.compactionEntry.id) || !supportsCacheWarm(ctx.model)) return;
    attempted.add(event.compactionEntry.id);

    cancel();
    const controller = new AbortController();
    active = controller;
    ctx.ui.setStatus(STATUS_KEY, "warming compacted cache…");

    try {
      await warmCompactedContext(pi, ctx, { signal: controller.signal });
    } catch {
      if (!controller.signal.aborted && ctx.hasUI) {
        ctx.ui.notify(
          "Compaction succeeded, but cache warm-up failed; the next turn will continue normally. Provider details withheld.",
          "warning",
        );
      }
    } finally {
      if (active === controller) {
        active = undefined;
        ctx.ui.setStatus(STATUS_KEY, undefined);
      }
    }
  });
}
