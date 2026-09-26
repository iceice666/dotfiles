import { describe, expect, test } from "bun:test";
import { realpathSync, mkdtempSync, rmSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { runPlan } from "../io.ts";
import { executionDecision } from "../index.ts";

const command = realpathSync(process.execPath);
const plan = (script: string, cleanup?: () => void) => ({ command, args: ["-e", script], options: { cwd: tmpdir(), env: {} }, cleanup });

describe("restricted transport", () => {
  test("captures exit status and always cleans up", async () => {
    let cleaned = 0;
    const result = await runPlan(plan("process.stdout.write('hello'); process.exitCode=3", () => cleaned++));
    expect(result.output.toString()).toBe("hello");
    expect(result.exitCode).toBe(3);
    expect(cleaned).toBe(1);
  });
  test("refuses output overflow and cleans up", async () => {
    let cleaned = 0;
    await expect(runPlan(plan("process.stdout.write('x'.repeat(10000))", () => cleaned++), { maxBytes: 20 })).rejects.toThrow("output limit");
    expect(cleaned).toBe(1);
  });
  test("timeout and already cancelled operations cannot succeed", async () => {
    await expect(runPlan(plan("setInterval(()=>{},1000)"), { timeout: 0.02 })).rejects.toThrow("timed out");
    let cleaned = 0;
    await expect(runPlan(plan("process.exit(0)", () => cleaned++), { signal: AbortSignal.abort() })).rejects.toThrow();
    expect(cleaned).toBe(1);
  });
  test("unknown tool names do not inherit classifier approvals", () => {
    expect(executionDecision("untrusted_tool")?.block).toBe(true);
    expect(executionDecision("powershell")?.block).toBe(true);
    expect(executionDecision("grep")?.block).toBe(true);
    expect(executionDecision("bash")).toBeUndefined();
    expect(executionDecision("background_task")).toBeUndefined();
    expect(executionDecision("todo")).toBeUndefined();
  });
});

// Module configuration is captured at import. Run a fresh process with a private
// workspace and immutable Nix tools, never with the test process's host scope.
test.skipIf(process.platform !== "darwin")("file operations use the real OS boundary", async () => {
  const root = mkdtempSync(join(tmpdir(), "pi-io-test-"));
  const workspace = join(root, "workspace");
  const { mkdirSync } = await import("node:fs");
  mkdirSync(workspace);
  writeFileSync(join(root, "outside"), "sentinel");
  const pinned = (name: string) => {
    const path = (process.env.PATH ?? "").split(":").map(dir => join(dir, name)).find(path => existsSync(path) && realpathSync(path).startsWith("/nix/store/"));
    if (!path) throw new Error(`Live sandbox test needs Nix-pinned ${name} on PATH`);
    return realpathSync(path);
  };
  const executable = pinned("bun");
  const script = `
    const {fileOperation,sandboxRead}=await import(${JSON.stringify(new URL("../io.ts", import.meta.url).pathname)});
    const root=${JSON.stringify(workspace)};
    await fileOperation('write',root+'/ok',root,root,undefined,'hello');
    if((await sandboxRead(root+'/ok',root,root)).toString()!=='hello') throw Error('read mismatch');
    let denied=false;
    try { await sandboxRead(root+'/../outside',root,root); } catch { denied=true; }
    if(!denied) throw Error('outside file escaped sandbox');
  `;
  try {
    const env: Record<string, string> = { PI_EXECUTION_WORKSPACE: workspace };
    for (const name of ["NODE", "BASH", "GIT", "ENV"]) env[`PI_SANDBOX_${name}`] = pinned(name.toLowerCase());
    env.PI_SANDBOX_PATH = [...new Set(Object.values(env).filter(value => value.startsWith("/nix/store/")).map(value => value.slice(0, value.lastIndexOf("/"))))].join(":");
    const result = await runPlan({ command: executable, args: ["-e", script], options: { cwd: workspace, env } });
    if (result.exitCode !== 0) throw new Error(result.output.toString());
    expect(result.output.toString()).toBe("");
    expect(readFileSync(join(workspace, "ok"), "utf8")).toBe("hello");
  } finally { rmSync(root, { recursive: true, force: true }); }
});
