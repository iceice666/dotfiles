// Discovers chat models from an OpenAI-compatible local server (llama-server,
// vLLM, LM Studio, Ollama's /v1, ...). Absent or failing servers yield no models.

export const DEFAULT_LOCAL_MODELS_URL = "http://localhost:8080";
const PROBE_TIMEOUT_MS = 2_000;
const DEFAULT_CONTEXT_WINDOW = 128_000;

export interface LocalChatModel {
  id: string;
  name: string;
  reasoning: boolean;
  thinkingLevelMap?: Record<string, string | null>;
  input: ("text" | "image")[];
  cost: { input: number; output: number; cacheRead: number; cacheWrite: number };
  contextWindow: number;
  maxTokens: number;
  compat: Record<string, unknown>;
}

/** Server root without trailing slash or `/v1`. */
export function normalizeServerUrl(value: string | undefined): string {
  const raw = value?.trim() || DEFAULT_LOCAL_MODELS_URL;
  return raw.replace(/\/+$/, "").replace(/\/v1$/, "");
}

type Fetch = (url: string, init: { signal: AbortSignal }) => Promise<Response>;

async function getJson(fetcher: Fetch, url: string, signal: AbortSignal): Promise<any> {
  const response = await fetcher(url, { signal: AbortSignal.any([signal, AbortSignal.timeout(PROBE_TIMEOUT_MS)]) });
  if (!response.ok) throw new Error(`${url}: HTTP ${response.status}`);
  return response.json();
}

/** Converts `/v1/models` plus optional llama-server `/props` into Pi chat models. */
export function toModels(list: any, props?: any): LocalChatModel[] {
  const entries: any[] = Array.isArray(list?.data) ? list.data : [];
  const propsCtx = props?.default_generation_settings?.n_ctx;
  const reasoning = typeof props?.chat_template === "string" && props.chat_template.includes("enable_thinking");
  const vision = props?.modalities?.vision === true;
  return entries
    .filter((entry) => typeof entry?.id === "string" && entry.id)
    .map((entry) => {
      const ctx = [entry.meta?.n_ctx, propsCtx, entry.context_length, entry.max_model_len]
        .find((value) => Number.isSafeInteger(value) && value > 0) ?? DEFAULT_CONTEXT_WINDOW;
      return {
        id: entry.id,
        name: `${entry.id} (local)`,
        reasoning,
        ...(reasoning && {
          thinkingLevelMap: { off: "off", minimal: null, low: null, medium: "medium", high: null, xhigh: null },
        }),
        input: vision ? ["text", "image"] : ["text"],
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
        contextWindow: ctx,
        maxTokens: ctx,
        compat: {
          supportsStore: false,
          supportsDeveloperRole: false,
          supportsReasoningEffort: false,
          supportsUsageInStreaming: true,
          supportsStrictMode: false,
          maxTokensField: "max_tokens",
          ...(reasoning && { thinkingFormat: "qwen-chat-template" }),
        },
      } satisfies LocalChatModel;
    });
}

/** Lists models; returns [] when the server is unreachable or not OpenAI-compatible. */
export async function discoverModels(serverUrl: string, signal: AbortSignal, fetcher: Fetch = fetch): Promise<LocalChatModel[]> {
  let list: any;
  try {
    list = await getJson(fetcher, `${serverUrl}/v1/models`, signal);
  } catch {
    return [];
  }
  // `/props` is llama-server specific (context size, thinking template, vision).
  const props = await getJson(fetcher, `${serverUrl}/props`, signal).catch(() => undefined);
  return toModels(list, props);
}
