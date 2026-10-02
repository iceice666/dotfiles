import { describe, expect, test } from "bun:test";
import { attestRuntime, managedRoot, type ToolSource } from "../boundary.ts";

const root = `/nix/store/${"a".repeat(32)}-pi-extensions`;
const builtin = (name: string): ToolSource => ({ name, sourceInfo: { source: "builtin", path: `<builtin:${name}>` } });
const managedTools = [
  ...["read", "bash", "powershell", "write", "edit", "grep", "find", "ls"].map(builtin),
  { name: "background_task", sourceInfo: { source: "cli", path: `${root}/background-task/index.ts` } },
];
const attest = (tool: ToolSource) => attestRuntime({ root, tools: [tool], toolName: tool.name });

describe("managed tool provenance", () => {
  test("only the content-addressed managed tree counts as managed", () => {
    expect(managedRoot(`${root}/auto-mode/index.ts`)).toBe(root);
    for (const path of ["/Users/me/.pi/agent/extensions/auto-mode/index.ts", "/nix/store/short-pi-extensions/auto-mode/index.ts", `/nix/store/${"a".repeat(32)}-other/auto-mode/index.ts`]) {
      expect(managedRoot(path)).toBeUndefined();
    }
    for (const unmanaged of [undefined, "/tmp/pi-extensions"]) {
      expect(attestRuntime({ root: unmanaged, tools: managedTools, toolName: "bash" }).managed).toBe(false);
    }
  });

  test("upstream native tools and managed extensions need no sandbox configuration or read/bash overrides", () => {
    for (const tool of managedTools) expect(attest(tool)).toEqual({ managed: true, reason: "" });
    expect(attestRuntime({ root, tools: managedTools, toolName: "background_task" }).managed).toBe(true);
  });

  test("builtin provenance requires the exact upstream name, path, and source", () => {
    for (const tool of [
      { name: "bash", sourceInfo: { path: "<builtin:bash>" } },
      { name: "bash", sourceInfo: { source: "sdk", path: "<builtin:bash>" } },
      { name: "bash", sourceInfo: { source: "cli", path: "<builtin:bash>" } },
      { name: "bash", sourceInfo: { source: "builtin", path: "<builtin:read>" } },
      { name: "bash", sourceInfo: { source: "builtin", path: `${root}/bash.ts` } },
      builtin("unknown_executor"),
    ]) expect(attest(tool).managed).toBe(false);
  });

  test("foreign, SDK, missing and escaped extension sources stay blocked", () => {
    for (const tool of [
      { name: "bash" },
      { name: "bash", sourceInfo: { source: "cli", path: "/tmp/bash.ts" } },
      { name: "bash", sourceInfo: { source: "cli", path: `${root}-foreign/bash.ts` } },
      { name: "bash", sourceInfo: { source: "cli", path: `${root}/../elsewhere/bash.ts` } },
      { name: "bash", sourceInfo: { source: "sdk", path: `${root}/bash.ts` } },
      { name: "bash", sourceInfo: { path: `${root}/bash.ts` } },
      { name: "bash", sourceInfo: { source: "cli", path: root } },
    ]) expect(attest(tool).managed).toBe(false);
    expect(attestRuntime({ root, tools: managedTools, toolName: "unregistered" }).managed).toBe(false);
  });
});
