import { describe, expect, test } from "bun:test";
import { mkdtempSync, mkdirSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { evaluatePolicy, actionForTool } from "../policy.ts";
import { guardTool } from "../gate.ts";

const cwd = process.cwd();
const signal = () => new AbortController().signal;
const action = (toolName: string, input: Record<string, unknown>) => actionForTool(toolName, input, cwd);

describe("local policy", () => {
  test("no shell prefix fast path; background commands share policy and actual cwd", () => {
    for (const command of ["git status", "git status\nprintf MARKER", "git status & printf MARKER", "git branch test", "git diff --output=/tmp/x", "printf 'a  b'"]) {
      expect(evaluatePolicy(action("bash", { command })).decision).toBe("review");
      expect(evaluatePolicy(action("background_task", { action: "start", command })).decision).toBe("review");
    }
    expect(action("background_task", { action: "start", command: "pwd", cwd: "../" }).cwd).toBe(join(cwd, ".."));
  });
  test("known local coordination and job observation do not require classifier", () => {
    expect(evaluatePolicy(action("todo", { action: "list" })).decision).toBe("allow");
    expect(evaluatePolicy(action("background_task", { action: "wait" })).decision).toBe("allow");
    expect(evaluatePolicy(action("background_task", { action: "unknown" })).decision).toBe("review");
    expect(evaluatePolicy(action("agent_spawn", { task: "do something" })).decision).toBe("review");
  });
  test("search egress and unknown tools never silently pass", () => {
    expect(evaluatePolicy(action("web_search", { query: "hello" })).decision).toBe("review");
    expect(evaluatePolicy(action("new_tool", {})).decision).toBe("review");
  });
  test("credential arguments blocked before model and controls require human", () => {
    expect(evaluatePolicy(action("read", { path: ".env" })).decision).toBe("block");
    expect(evaluatePolicy(action("write", { path: ".pi/settings.json", content: "{}" })).decision).toBe("ask");
    expect(evaluatePolicy(action("write", { path: "AGENTS.md", content: "new policy" })).decision).toBe("ask");
    expect(evaluatePolicy(action("bash", { command: "cat ~/.ssh/id_ed25519" })).decision).toBe("ask");
    expect(evaluatePolicy(action("web_search", { query: "-----BEGIN PRIVATE KEY-----" })).decision).toBe("block");
  });
  test("alternate SDK paths are rejected rather than misclassified", () => {
    for (const path of ["file:///tmp/outside", "file:///tmp/%2epi/auth.json", "@file:///tmp/outside", "space\u00a0name"]) {
      expect(() => evaluatePolicy(action("write", { path, content: "x" }))).toThrow();
    }
  });
  test("outside-workspace controls still require explicit human review", () => {
    expect(evaluatePolicy(action("write", { path: "/tmp/.pi/settings.json", content: "x" })).decision).toBe("ask");
  });
  test("symlink escapes do not use workspace fast path", () => {
    const dir = mkdtempSync(join(tmpdir(), "auto-policy-"));
    try {
      mkdirSync(join(dir, "repo")); mkdirSync(join(dir, "outside"));
      symlinkSync(join(dir, "outside"), join(dir, "repo", "link"));
      symlinkSync(join(dir, "outside", "missing"), join(dir, "repo", "dangling"));
      expect(() => evaluatePolicy({ toolName: "write", input: { path: "dangling", content: "x" }, cwd: join(dir, "repo") })).toThrow();
      writeFileSync(join(dir, "outside", "file"), "test");
      symlinkSync(join(dir, "outside", "file"), join(dir, "repo", "capture’image"));
      expect(() => evaluatePolicy({ toolName: "read", input: { path: "capture'image" }, cwd: join(dir, "repo") })).toThrow();
      for (const path of ["link/file", "link/new"]) expect(evaluatePolicy({ toolName: "write", input: { path, content: "x" }, cwd: join(dir, "repo") }).decision).toBe("review");
    } finally { rmSync(dir, { recursive: true, force: true }); }
  });
});

describe("gate", () => {
  test("reviews exact raw command afresh on every execution", async () => {
    const seen: string[] = [];
    const input = { command: "printf 'a  b'\nprintf second" };
    const services = { classify: async (a: ReturnType<typeof action>) => { seen.push(String(a.input.command)); return { decision: "allow" as const, reason: "safe" }; }, approve: async () => false };
    expect(await guardTool("bash", input, cwd, services, signal())).toBeUndefined();
    expect(await guardTool("bash", input, cwd, services, signal())).toBeUndefined();
    expect(seen).toEqual([input.command, input.command]);
  });
  test("review failure requests real approval, not implicit allow", async () => {
    for (const approved of [true, false]) {
      const result = await guardTool("bash", { command: "test" }, cwd, { classify: async () => { throw new Error("secret error"); }, approve: async () => approved }, signal());
      expect(result === undefined).toBe(approved);
      if (result) expect(result.reason).not.toContain("secret error");
    }
  });
  test("deny cannot be overridden via approval callback", async () => {
    let asked = false;
    const result = await guardTool("bash", { command: "test" }, cwd, { classify: async () => ({ decision: "deny", reason: "unsafe" }), approve: async () => { asked = true; return true; } }, signal());
    expect(result?.block).toBe(true); expect(asked).toBe(false);
  });
  test("cancellation wins even over late human approval", async () => {
    const abort = new AbortController();
    const result = await guardTool("write", { path: "AGENTS.md", content: "x" }, cwd, { classify: async () => { throw new Error(); }, approve: async () => { abort.abort(); return true; } }, abort.signal);
    expect(result?.block).toBe(true);
  });
  test("rejects argument mutation while waiting", async () => {
    const input = { command: "first" };
    const result = await guardTool("bash", input, cwd, { classify: async () => { input.command = "second"; return { decision: "allow", reason: "safe" }; }, approve: async () => true }, signal());
    expect(result?.block).toBe(true);
  });
  test("oversized action cannot be approved unseen", async () => {
    let called = false;
    const result = await guardTool("bash", { command: "x".repeat(40000) }, cwd, { classify: async () => { called = true; return { decision: "allow", reason: "safe" }; }, approve: async () => true }, signal());
    expect(result?.block).toBe(true); expect(called).toBe(false);
  });
});
