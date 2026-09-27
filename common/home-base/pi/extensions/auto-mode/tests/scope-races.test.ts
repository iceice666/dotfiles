import { expect, test } from "bun:test";
import { guardTool } from "../gate.ts";
import { mergeParentContext } from "../service.ts";
import type { ReviewContext } from "../classifier.ts";

test("cancellation after an asynchronous scope or freshness check cannot execute", async () => {
  for (const location of ["scope", "current"]) {
    const abort = new AbortController();
    const result = await guardTool("write", { path: "extensions/file.ts", content: "x" }, process.cwd(), {
      classify: async () => ({ decision: "allow", reason: "routine" }), approve: async () => true,
      scope: async () => async () => { if (location === "scope") abort.abort(); return true; },
      isCurrent: async () => { if (location === "current") abort.abort(); return true; },
    }, abort.signal);
    expect(result?.block).toBe(true);
  }
});

test("parent recent context accumulates against the budget, not per item", () => {
  const base: ReviewContext = { version: 1, sessionId: "child", leafId: null, memoryStatus: "available", memory: [], recent: [], evidence: [], coverageId: null, truncated: false };
  const parent = { ...base, sessionId: "parent", recent: Array.from({ length: 8 }, (_, i) => ({ id: String(i), role: "user" as const, text: "界".repeat(450) })) };
  const result = mergeParentContext(base, parent);
  expect(Buffer.byteLength(JSON.stringify(result))).toBeLessThan(4500);
  expect(result.truncated).toBe(true);
  expect(result.recent.at(-1)?.id).toBe("parent:parent:7");
});
