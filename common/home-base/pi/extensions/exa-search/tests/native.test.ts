import { describe, expect, test } from "bun:test";
import { nativeRequest, parseNative } from "../native.ts";

const url = "https://example.org/article";
const openai = (output: unknown[], status = "completed") => ({ status, output });
const search = (sources: unknown[] = []) => ({ type: "web_search_call", status: "completed", action: { type: "search", sources } });
const message = (text = "Summary", annotations: unknown[] = []) => ({ type: "message", role: "assistant", content: [{ type: "output_text", text, annotations }] });
const claude = (content: unknown[], stop_reason = "end_turn") => ({ type: "message", role: "assistant", content, stop_reason });
const use = { type: "server_tool_use", name: "web_search", id: "search-1", input: { query: "example" } };
const result = (content: unknown = []) => ({ type: "web_search_tool_result", tool_use_id: "search-1", content });

describe("native requests", () => {
  test("OpenAI requests native search and included sources without streaming", () => {
    expect(nativeRequest("openai", "example", 3)).toMatchObject({
      model: "gpt-6-astra", stream: false, max_output_tokens: 4096,
      tools: [{ type: "web_search" }], tool_choice: "required",
      include: ["web_search_call.action.sources"],
    });
    expect(JSON.stringify(nativeRequest("openai", "example", 3))).toContain("up to 3");
  });
  test("Claude limits native tool uses", () => {
    expect(nativeRequest("claude", "example", 3)).toMatchObject({
      model: "claude-sonnet-5", stream: false, max_tokens: 4096,
      tools: [{ type: "web_search_20250305", name: "web_search", max_uses: 2 }],
    });
  });
});

describe("OpenAI native parsing", () => {
  test("merges sources and citations, preserves URLs and excludes reasoning", () => {
    const longUrl = `${url}?query=${"a".repeat(3000)}`;
    expect(parseNative("openai", openai([
      { type: "reasoning", summary: [{ text: "private reasoning" }] },
      search([{ type: "url", url }, { type: "url", url: longUrl }]),
      message("Summary", [{ type: "url_citation", url, title: "Example", start_index: 0, end_index: 7 }]),
    ]))).toEqual({ results: [{ url, title: "Example" }, { url: longUrl }], summary: "Summary", incomplete: false });
  });
  test("allows completed empty search and flags incomplete response", () => {
    expect(parseNative("openai", openai([search()], "incomplete"))).toEqual({ results: [], summary: "", incomplete: true });
  });
  test("supports citations when action sources are absent", () => {
    expect(parseNative("openai", openai([
      { type: "web_search_call", status: "completed" },
      message("Answer", [{ type: "url_citation", url }]),
    ])).results).toEqual([{ url }]);
  });
  test("plain answers, failed calls, invalid statuses and errors are rejected safely", () => {
    for (const data of [
      null, {}, { status: "failed", output: [] }, openai([message()]),
      { ...openai([search()]), error: { message: "SECRET" } },
      openai([{ type: "web_search_call", status: "failed", error: "SECRET" }]),
      openai([{ type: "web_search_call", status: "in_progress" }]),
      openai([search(), { type: "message", role: "assistant", content: "SECRET" }]),
      openai([search([{ url: 42 }])]),
    ]) {
      expect(() => parseNative("openai", data)).toThrow("Native web search returned an invalid or unsuccessful response.");
    }
  });
});

describe("Claude native parsing", () => {
  test("requires linked search and merges result metadata with cited excerpts", () => {
    expect(parseNative("claude", claude([
      { type: "thinking", thinking: "private reasoning" }, use,
      result([{ type: "web_search_result", url, title: "Example", encrypted_content: "opaque" }]),
      { type: "text", text: "Summary", citations: [{ type: "web_search_result_location", url, title: "Example", cited_text: "Excerpt" }] },
    ]))).toEqual({ results: [{ url, title: "Example", text: "Excerpt" }], summary: "Summary", incomplete: false });
  });
  test("empty successful results work and continuation reasons are incomplete", () => {
    for (const reason of ["max_tokens", "pause_turn"]) {
      expect(parseNative("claude", claude([use, result()], reason))).toEqual({ results: [], summary: "", incomplete: true });
    }
  });
  test("rejects unlinked results, tool errors and malformed output safely", () => {
    for (const data of [
      claude([{ type: "text", text: "Answer" }]), claude([result()]), claude([use]),
      claude([use, { ...result(), tool_use_id: "unknown" }]),
      claude([use, result({ type: "web_search_tool_result_error", error_code: "SECRET" })]),
      claude([use, result([{ type: "web_search_tool_result_error", error_code: "SECRET" }])]),
      claude([use, { ...result(), is_error: true }]),
      claude([use, result()], "tool_use"),
      { type: "error", error: { message: "SECRET" } },
      claude([use, result(), { type: "text", text: 42 }]),
    ]) {
      expect(() => parseNative("claude", data)).toThrow("Native web search returned an invalid or unsuccessful response.");
    }
  });
});

test("both adapters reject unsafe source URLs instead of altering links", () => {
  for (const unsafe of ["javascript:alert(1)", "file:///etc/passwd", "https://user:pass@example.org", "https://example.org/\nspoof", "not a URL"]) {
    expect(() => parseNative("openai", openai([search([{ url: unsafe }])]))).toThrow();
    expect(() => parseNative("claude", claude([use, result([{ type: "web_search_result", url: unsafe }])]))).toThrow();
  }
});
