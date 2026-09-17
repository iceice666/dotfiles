import { afterEach, describe, expect, test } from "bun:test";
import { mkdtemp, readFile, rm, truncate, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import type { AssistantMessage, Model, Api } from "@earendil-works/pi-ai";
import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import { analyzeImage, DEFAULT_MODEL, imageMime, loadImage, MAX_IMAGE_BYTES } from "../analyze.ts";
import extension from "../index.ts";

const dirs: string[] = [];
afterEach(async () => { await Promise.all(dirs.splice(0).map(dir => rm(dir, { recursive: true, force: true }))); });
const png = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aWQAAAABJRU5ErkJggg==", "base64");
const model = { provider: "cliproxyapi-claude", id: "claude-sonnet-5", input: ["text", "image"], maxTokens: 128000 } as Model<Api>;
const usage = { input: 10, output: 5, cacheRead: 0, cacheWrite: 0, totalTokens: 15, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } };
function reply(overrides: Partial<AssistantMessage> = {}): AssistantMessage {
  return { role: "assistant", api: "anthropic-messages", provider: model.provider, model: model.id, timestamp: 0, stopReason: "stop", content: [{ type: "text", text: "A white pixel." }], usage, ...overrides };
}
type Registry = Pick<ExtensionContext["modelRegistry"], "find" | "complete">;
function registry(response = reply()): Registry {
  return { find: () => model, complete: async () => response };
}
async function fixture() {
  const dir = await mkdtemp(join(tmpdir(), "pi-image-test-"));
  dirs.push(dir);
  await writeFile(join(dir, "pixel.png"), png);
  return dir;
}
const input = { path: "pixel.png", question: "What is visible?" };

describe("analyze_image", () => {
  test("registers a text-result tool with strict schema", () => {
    let tool: any;
    extension({ registerTool: (value: unknown) => { tool = value; } } as any);
    expect(tool.name).toBe("analyze_image");
    expect(tool.parameters.additionalProperties).toBe(false);
    expect(tool.parameters.required).toEqual(["path", "question"]);
  });

  test("sends only the question and image, uses registry auth, and accounts usage", async () => {
    const cwd = await fixture();
    let called = false;
    const r: Registry = {
      find(provider, id) { expect(`${provider}/${id}`).toBe(DEFAULT_MODEL); return model; },
      async complete(_model, context, options) {
        called = true;
        expect(context.tools).toBeUndefined();
        expect(context.messages).toHaveLength(1);
        expect(context.messages[0].content).toEqual([
          { type: "text", text: input.question }, { type: "image", mimeType: "image/png", data: png.toString("base64") },
        ]);
        expect(options).toMatchObject({ maxTokens: 4096, maxRetries: 0, timeoutMs: 120000, cacheRetention: "none" });
        expect(options?.signal).toBeInstanceOf(AbortSignal);
        return reply({ content: [{ type: "thinking", thinking: "private thought" }, { type: "text", text: "A white pixel." }] });
      },
    };
    const result = await analyzeImage(input, cwd, r);
    expect(called).toBe(true);
    expect(result.usage).toEqual(usage);
    expect(result.content[0].text).toContain("A white pixel.");
    expect(JSON.stringify(result)).not.toContain("private thought");
    expect(JSON.stringify(result)).not.toContain(png.toString("base64"));
    expect(result.content.every(part => part.type === "text")).toBe(true);
    expect(result.details.fullOutputPath).toBeUndefined();
  });

  test("supports explicit model and leading @ relative path", async () => {
    const cwd = await fixture();
    const r = registry();
    r.find = (provider, id) => { expect(provider).toBe("other"); expect(id).toBe("vision/model"); return model; };
    const result = await analyzeImage({ ...input, path: "@pixel.png", model: "other/vision/model" }, cwd, r);
    expect(result.details.model).toBe("other/vision/model");
  });

  test("rejects missing/text-only models and invalid question before making requests", async () => {
    const r = registry();
    r.complete = async () => { throw new Error("must not call"); };
    await expect(analyzeImage({ ...input, question: " " }, "/", r)).rejects.toThrow("Question");
    await expect(analyzeImage({ ...input, model: "bare" }, "/", r)).rejects.toThrow("provider/model-id");
    r.find = () => undefined;
    await expect(analyzeImage(input, "/", r)).rejects.toThrow("not configured");
    r.find = () => ({ ...model, input: ["text"] });
    await expect(analyzeImage(input, "/", r)).rejects.toThrow("does not declare image");
  });

  test("validates signatures, rejects URLs, empty/oversized files and directories", async () => {
    const cwd = await fixture();
    const signal = new AbortController().signal;
    expect(imageMime(Buffer.from([255, 216, 255]))).toBe("image/jpeg");
    expect(imageMime(Buffer.from("GIF89a"))).toBe("image/gif");
    expect(imageMime(Buffer.from("RIFF0000WEBP"))).toBe("image/webp");
    for (const path of ["https://example.com/x.png", "data:image/png;base64,abc", "."]) {
      await expect(loadImage(path, cwd, signal)).rejects.toThrow();
    }
    await writeFile(join(cwd, "bad.png"), "not an image");
    await expect(loadImage("bad.png", cwd, signal)).rejects.toThrow("signature");
    await writeFile(join(cwd, "empty.png"), "");
    await expect(loadImage("empty.png", cwd, signal)).rejects.toThrow("nonempty");
    await truncate(join(cwd, "empty.png"), MAX_IMAGE_BYTES + 1);
    await expect(loadImage("empty.png", cwd, signal)).rejects.toThrow("5 MiB");
    await expect(loadImage("missing.png", cwd, signal)).rejects.toThrow();
  });

  test("redacts provider errors and rejects empty/tool/incomplete responses", async () => {
    const cwd = await fixture();
    for (const stopReason of ["error", "aborted", "toolUse", "pending", "deferred"] as const) {
      await expect(analyzeImage(input, cwd, registry(reply({ stopReason, errorMessage: "SECRET" })))).rejects.not.toThrow("SECRET");
    }
    await expect(analyzeImage(input, cwd, registry(reply({ content: [] })))).rejects.toThrow("no analysis");
    await expect(analyzeImage(input, cwd, registry(reply({ content: [{ type: "toolCall", id: "bad", name: "bash", arguments: {} }] })))).rejects.toThrow("unexpected tool call");
    const r = registry();
    r.complete = async () => { throw new Error("SECRET"); };
    await expect(analyzeImage(input, cwd, r)).rejects.toThrow("details withheld");
  });

  test("flags token-limit and output truncation; saves private full text", async () => {
    const cwd = await fixture();
    const text = "visible evidence\n".repeat(1000);
    const result = await analyzeImage(input, cwd, registry(reply({ stopReason: "length", content: [{ type: "text", text }] })));
    expect(result.details.limited).toBe(true);
    expect(result.details.truncated).toBe(true);
    expect(result.content[0].text).toContain("token limit");
    dirs.push(dirname(result.details.fullOutputPath!));
    expect(await readFile(result.details.fullOutputPath!, "utf8")).toBe(text.trim());
    expect(result.content[0].text.length).toBeLessThan(25000);
  });

  test("bounds multibyte single-line output by bytes", async () => {
    const cwd = await fixture();
    const text = "圖片".repeat(10000);
    const result = await analyzeImage(input, cwd, registry(reply({ content: [{ type: "text", text }] })));
    dirs.push(dirname(result.details.fullOutputPath!));
    expect(result.details.truncated).toBe(true);
    expect(Buffer.byteLength(result.content[0].text)).toBeLessThan(25 * 1024);
    expect(result.content[0].text).not.toContain("�");
  });

  test("active cancellation aborts the provider signal", async () => {
    const cwd = await fixture();
    const controller = new AbortController();
    const r = registry();
    let requestSignal: AbortSignal | undefined;
    r.complete = async (_model, _context, options) => {
      requestSignal = options?.signal;
      controller.abort();
      return new Promise(() => {});
    };
    await expect(analyzeImage(input, cwd, r, controller.signal)).rejects.toThrow("cancelled");
    expect(requestSignal?.aborted).toBe(true);
  });

  test("pre-cancellation makes no provider call", async () => {
    const controller = new AbortController();
    controller.abort();
    let called = false;
    const r = registry();
    r.complete = async () => { called = true; return reply(); };
    await expect(analyzeImage(input, "/", r, controller.signal)).rejects.toThrow("cancelled");
    expect(called).toBe(false);
  });

  test("deadline stops waiting even if provider ignores cancellation", async () => {
    const cwd = await fixture();
    const r = registry();
    let requestSignal: AbortSignal | undefined;
    r.complete = async (_model, _context, options) => {
      requestSignal = options?.signal;
      return new Promise(() => {});
    };
    await expect(analyzeImage(input, cwd, r, undefined, 30)).rejects.toThrow("timed out");
    expect(requestSignal?.aborted).toBe(true);
  });
});
