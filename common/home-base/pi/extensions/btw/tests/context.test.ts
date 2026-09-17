import { expect, test } from "bun:test";
import { type SessionEntry } from "@earendil-works/pi-coding-agent";
import { conversationSnapshot, MAX_CONTEXT_CHARS } from "../context.ts";

const stamp = "2026-01-01T00:00:00.000Z";
function chain(items: any[]): SessionEntry[] {
  return items.map((item, i) => ({ id: String(i), parentId: i ? String(i - 1) : null, timestamp: stamp, ...item }));
}
const user = (text: string) => ({ type: "message", message: { role: "user", content: text, timestamp: 0 } });

test("empty conversation and UI-only BTW entries contribute no context", () => {
  expect(conversationSnapshot([])).toBe("");
  const entries = chain([user("main task"), { type: "custom", customType: "btw-answer", data: { question: "SIDE QUESTION", answer: "SIDE ANSWER" } }]);
  expect(conversationSnapshot(entries)).toBe("user: main task");
});

test("text snapshot omits thinking, image payloads, signatures and tool details", () => {
  const entries = chain([
    user("question"),
    { type: "message", message: { role: "assistant", content: [
      { type: "thinking", thinking: "PRIVATE THOUGHT", thinkingSignature: "PRIVATE SIGNATURE" },
      { type: "text", text: "visible response" },
      { type: "toolCall", id: "call-1", name: "read", arguments: { path: "file.txt" } },
    ] } },
    { type: "message", message: { role: "toolResult", toolCallId: "call-1", toolName: "read", content: [
      { type: "text", text: "visible result" }, { type: "image", data: "PRIVATE IMAGE", mimeType: "image/png" },
    ], details: { hidden: "PRIVATE DETAILS" } } },
  ]);
  const result = conversationSnapshot(entries);
  expect(result).toContain("visible response");
  expect(result).toContain("visible result");
  expect(result).toContain("Tool call: read");
  expect(result).not.toContain("PRIVATE");
});

test("compaction summary keeps retained tail and post-compaction messages", () => {
  const entries = chain([
    user("summarized old content"), user("retainedTail"),
    { type: "compaction", summary: "compact summary", firstKeptEntryId: "1", tokensBefore: 100 },
    user("newest message"),
  ]);
  const result = conversationSnapshot(entries);
  expect(result).toContain("compact summary");
  expect(result).toContain("retainedTail");
  expect(result).toContain("newest message");
  expect(result).not.toContain("summarized old content");
});

test("snapshot taken immediately after compaction retains summary and kept messages", () => {
  const entries = chain([
    user("old"), user("retainedTail"),
    { type: "compaction", summary: "compact summary", firstKeptEntryId: "1", tokensBefore: 100 },
  ]);
  const result = conversationSnapshot(entries);
  expect(result).toContain("compact summary");
  expect(result).toContain("retainedTail");
  expect(result).not.toContain("user: old");
});

test("bounds preserve recent context and mark omitted earlier context", () => {
  const entries = chain([user("oldest " + "x".repeat(MAX_CONTEXT_CHARS)), user("LATEST")]);
  for (const limit of [80, MAX_CONTEXT_CHARS]) {
    const result = conversationSnapshot(entries, limit);
    expect(result).toContain("[Earlier context omitted; recent snapshot only]");
    expect(result.endsWith("user: LATEST")).toBe(true);
    expect(result.length).toBeLessThanOrEqual(limit + "[Earlier context omitted; recent snapshot only]\n".length);
    expect(result).not.toContain("oldest");
  }
});

test("bash exclusion and branch summary are respected", () => {
  const entries = chain([
    { type: "message", message: { role: "bashExecution", command: "echo visible", output: "visible output" } },
    { type: "message", message: { role: "bashExecution", command: "PRIVATE COMMAND", output: "PRIVATE OUTPUT", excludeFromContext: true } },
    { type: "branch_summary", summary: "branch facts", fromId: "other-branch" },
  ]);
  const result = conversationSnapshot(entries);
  expect(result).toContain("visible output");
  expect(result).toContain("branch facts");
  expect(result).not.toContain("PRIVATE");
});
