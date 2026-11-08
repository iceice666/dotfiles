import { expect, test } from "bun:test";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import register from "../index.ts";
import { discoverModels, normalizeServerUrl, toModels } from "../discovery.ts";

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status });

test("normalizes the server root", () => {
  expect(normalizeServerUrl(undefined)).toBe("http://localhost:8080");
  expect(normalizeServerUrl(" http://127.0.0.1:1234/v1/ ")).toBe("http://127.0.0.1:1234");
});

test("maps llama-server models with props", () => {
  const [model] = toModels(
    { data: [{ id: "qwen", meta: { n_ctx: 131072 } }] },
    { chat_template: "{% if enable_thinking %}", modalities: { vision: true } },
  );
  expect(model).toMatchObject({ id: "qwen", reasoning: true, input: ["text", "image"], contextWindow: 131072, maxTokens: 131072 });
  expect(model.compat.thinkingFormat).toBe("qwen-chat-template");
});

test("generic servers get conservative defaults", () => {
  const models = toModels({ data: [{ id: "m" }, { id: "" }, {}] });
  expect(models).toHaveLength(1);
  expect(models[0]).toMatchObject({ reasoning: false, input: ["text"], contextWindow: 128000 });
});

test("unreachable server yields no models", async () => {
  const fetcher = async () => { throw new TypeError("fetch failed"); };
  expect(await discoverModels("http://localhost:1", new AbortController().signal, fetcher)).toEqual([]);
});

test("missing /props still lists models", async () => {
  const fetcher = async (url: string) => (url.endsWith("/v1/models") ? json({ data: [{ id: "x" }] }) : json({}, 404));
  expect((await discoverModels("http://h", new AbortController().signal, fetcher)).map(m => m.id)).toEqual(["x"]);
});

test("registers the local provider; offline skips the probe", async () => {
  const providers: [string, any][] = [];
  process.env.PI_OFFLINE = "1";
  await register({ registerProvider: (name: string, config: unknown) => providers.push([name, config]) } as unknown as ExtensionAPI);
  delete process.env.PI_OFFLINE;
  expect(providers).toHaveLength(1);
  const [name, config] = providers[0];
  expect(name).toBe("local");
  expect(config).toMatchObject({ api: "openai-completions", models: [] });
  expect(await config.refreshModels({ allowNetwork: false, signal: new AbortController().signal })).toEqual([]);
});
