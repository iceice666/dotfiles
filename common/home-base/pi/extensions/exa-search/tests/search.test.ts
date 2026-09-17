import { describe, expect, test } from "bun:test";
import { mkdtemp, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { ENDPOINT, MAX_OUTPUT_BYTES, MAX_OUTPUT_LINES, MAX_RESPONSE_BYTES, readKey, search, type Dependencies } from "../search.ts";

const result = { title: "Documentation", url: "https://example.com/docs", publishedDate: "2026-01-01", text: "An excerpt" };
function deps(overrides: Partial<Dependencies> = {}): Dependencies {
  return {
    getAgentDir: () => "/test/pi agent",
    readKey: async () => "test-key\n",
    fetch: async () => Response.json({ results: [result] }),
    ...overrides,
  };
}

describe("Exa search", () => {
  test("executes credential helper paths literally and sanitizes process failures", async () => {
    const directory = await mkdtemp(join(tmpdir(), "pi exa helper "));
    // Spaces and shell metacharacters must be literal parts of the filename.
    const helper = join(directory, "exa-api-key ; false");
    try {
      await writeFile(helper, "#!/bin/sh\nprintf 'synthetic-key\\n'\n", { mode: 0o700 });
      expect(await readKey(helper, new AbortController().signal)).toBe("synthetic-key\n");
      await writeFile(helper, "#!/bin/sh\nprintf 'SECRET STDOUT'\nprintf 'SECRET STDERR' >&2\nexit 1\n");
      await expect(readKey(helper, new AbortController().signal)).rejects.toThrow("Exa credential helper failed. Check the exa-api-key helper and SOPS activation.");
      await expect(readKey(join(directory, "missing"), new AbortController().signal)).rejects.toThrow("Exa credential helper failed. Check the exa-api-key helper and SOPS activation.");
    } finally {
      await rm(directory, { recursive: true, force: true });
    }
  });

  test("reads the helper at request time and sends bounded auto search", async () => {
    let reads = 0;
    const dependencies = deps({
      readKey: async (path, signal) => {
        expect(path).toBe("/test/pi agent/exa-api-key");
        expect(signal.aborted).toBe(false);
        return `key-${++reads}\n`;
      },
      fetch: async (url, init) => {
        expect(url).toBe(ENDPOINT);
        expect(init.method).toBe("POST");
        expect(init.redirect).toBe("error");
        expect(init.headers).toEqual({ "Content-Type": "application/json", "x-api-key": `key-${reads}` });
        expect(JSON.parse(init.body as string)).toEqual({ query: "nix docs", numResults: 5, type: "auto", contents: { text: { maxCharacters: 2000 } } });
        return Response.json({ results: [result] });
      },
    });
    const output = await search({ query: " nix docs " }, undefined, dependencies);
    expect(output.text).toContain(result.url);
    expect(output.text).toContain(result.publishedDate);
    expect(output.text).toContain("untrusted");
    expect(output.count).toBe(1);
    await search({ query: "nix docs" }, undefined, dependencies);
    expect(reads).toBe(2);
  });

  test("validates before credential or network access", async () => {
    let touched = false;
    const dependencies = deps({ readKey: async () => { touched = true; return "key"; } });
    for (const input of [{ query: " " }, { query: "x".repeat(2001) }, ...[0, 11, 1.5, NaN, null].map(numResults => ({ query: "ok", numResults }))]) {
      await expect(search(input as any, undefined, dependencies)).rejects.toThrow();
    }
    expect(touched).toBe(false);
  });

  test("empty results and missing optional fields", async () => {
    expect((await search({ query: "q" }, undefined, deps({ fetch: async () => Response.json({ results: [] }) }))).text).toBe("No web search results found.");
    expect((await search({ query: "q" }, undefined, deps({ fetch: async () => Response.json({ results: [{ url: result.url }] }) }))).text).toContain("No text excerpt");
  });

  test("HTTP and helper errors never expose upstream bodies or credentials, with no retry", async () => {
    for (const status of [401, 403, 429, 500]) {
      let calls = 0;
      await expect(search({ query: "q" }, undefined, deps({ fetch: async () => {
        calls++;
        return new Response("SENSITIVE SERVER BODY", { status });
      } }))).rejects.toThrow(`Exa search failed (HTTP ${status}). Check credentials, quota, or service availability.`);
      expect(calls).toBe(1);
    }
    await expect(search({ query: "q" }, undefined, deps({ readKey: async () => { throw new Error("SECRET STDERR"); } }))).rejects.toThrow("Exa credential helper failed. Check the exa-api-key helper and SOPS activation.");
    await expect(search({ query: "q" }, undefined, deps({ fetch: async () => { throw new Error("SECRET HEADERS"); } }))).rejects.toThrow("Exa search failed due to a network or response error.");
  });

  test("rejects invalid keys before fetching", async () => {
    for (const key of ["", "\n", "a\nb", "x".repeat(4097)]) {
      await expect(search({ query: "q" }, undefined, deps({ readKey: async () => key, fetch: async () => { throw new Error("must not fetch"); } }))).rejects.toThrow("invalid key");
    }
  });

  test("rejects malformed JSON, shape, unsafe URLs and oversized responses", async () => {
    for (const data of [null, {}, { results: [null] }, { results: [{ url: "javascript:alert(1)" }] }, { results: [{ url: "https://user:pass@example.com" }] }]) {
      await expect(search({ query: "q" }, undefined, deps({ fetch: async () => Response.json(data) }))).rejects.toThrow();
    }
    await expect(search({ query: "q" }, undefined, deps({ fetch: async () => new Response("not JSON SECRET") }))).rejects.toThrow("invalid JSON");
    await expect(search({ query: "q" }, undefined, deps({ fetch: async () => new Response("x".repeat(MAX_RESPONSE_BYTES + 1)) }))).rejects.toThrow("512 KiB");
  });

  test("bounds bytes, lines, result count, and strips terminal escapes", async () => {
    const many = Array.from({ length: 20 }, () => ({ ...result, title: "\u001bTITLE", text: "字\n".repeat(1500) }));
    const output = await search({ query: "q", numResults: 10 }, undefined, deps({ fetch: async () => Response.json({ results: many }) }));
    expect(Buffer.byteLength(output.text)).toBeLessThanOrEqual(MAX_OUTPUT_BYTES);
    expect(output.text.split("\n").length).toBeLessThanOrEqual(MAX_OUTPUT_LINES);
    expect(output.count).toBe(10);
    expect(output.truncated).toBe(true);
    expect(output.text).toContain("Output truncated");
    expect(output.text).not.toContain("\u001b");
    expect(output.text).not.toContain("�");
  });

  test("pre-abort does not invoke helpers", async () => {
    const controller = new AbortController();
    controller.abort("PRIVATE REASON");
    await expect(search({ query: "q" }, controller.signal, deps({ readKey: async () => { throw new Error("should not run"); } }))).rejects.toThrow("Web search cancelled.");
  });

  test("cancels in-flight requests even when a dependency ignores abort", async () => {
    const controller = new AbortController();
    let observed: AbortSignal | null | undefined;
    const pending = search({ query: "q" }, controller.signal, deps({ fetch: async (_url, init) => {
      observed = init.signal;
      controller.abort("PRIVATE REASON");
      return await new Promise<Response>(() => {});
    } }));
    await expect(pending).rejects.toThrow("Web search cancelled.");
    expect(observed?.aborted).toBe(true);
  });

  test("times out helper and stalled response body", async () => {
    await expect(search({ query: "q" }, undefined, deps({ timeoutMs: 5, readKey: async () => new Promise<string>(() => {}) }))).rejects.toThrow("Web search timed out.");
    await expect(search({ query: "q" }, undefined, deps({ timeoutMs: 5, fetch: async () => new Response(new ReadableStream({ start() {} })) }))).rejects.toThrow("Web search timed out.");
  });
});
