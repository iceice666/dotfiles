import { expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { join } from "node:path";

test("status line reports an unavailable sandbox instead of a working boundary", () => {
  const entry = join(import.meta.dir, "../index.ts");
  const script = `
    const policy = await import(${JSON.stringify(entry)});
    const handlers = new Map(); const statuses = {}; const notes = [];
    policy.default({ registerTool() {}, registerCommand() {}, on: (n, h) => handlers.set(n, h), setActiveTools() {}, getActiveTools: () => [] });
    handlers.get("session_start")({}, { cwd: process.cwd(), hasUI: true, ui: { setStatus: (k, v) => { statuses[k] = v; }, notify: (text, level) => notes.push([text, level]) } });
    console.log(JSON.stringify({ statuses, notes }));`;
  const env = Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.startsWith("PI_SANDBOX_")));
  const result = spawnSync(process.execPath, ["-e", script], { cwd: join(import.meta.dir, ".."), env, encoding: "utf8", timeout: 20000 });
  expect(result.status).toBe(0);
  const { statuses, notes } = JSON.parse(result.stdout.trim().split("\n").at(-1)!);
  expect(statuses["execution-policy"]).toBe("sandbox:UNAVAILABLE");
  expect(notes.some(([text, level]: string[]) => level === "error" && text.includes("managed `pi` launcher"))).toBe(true);
});
