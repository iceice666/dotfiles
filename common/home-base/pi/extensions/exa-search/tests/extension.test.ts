import { expect, test } from "bun:test";
import type { ExtensionAPI, ToolDefinition } from "@earendil-works/pi-coding-agent";
import register from "../index.ts";

test("registers web_search without startup I/O or UI requirements", async () => {
  const tools: ToolDefinition[] = [];
  register({ registerTool: (tool: ToolDefinition) => tools.push(tool) } as unknown as ExtensionAPI);
  expect(tools).toHaveLength(1);
  const tool = tools[0];
  expect(tool.name).toBe("web_search");
  expect(tool.parameters.properties.query.maxLength).toBe(2000);
  expect(tool.parameters.properties.numResults.maximum).toBe(10);
  expect(tool.parameters.additionalProperties).toBe(false);
  expect(tool.promptSnippet).toContain("Exa");
  expect(tool.promptGuidelines?.every(line => line.includes("web_search"))).toBe(true);
  const controller = new AbortController();
  controller.abort();
  await expect(tool.execute("test", { query: "public documentation" }, controller.signal, undefined, {} as any)).rejects.toThrow("Web search cancelled.");
});
