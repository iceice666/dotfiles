import { expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import guard from "../index.ts";
import { loadExtensions } from "../../agent-team/tests/sdk.ts";

function setup(hasUI = true) {
  const handlers = new Map<string, any>();
  const statuses = new Map<string, string>(), notes: any[] = [];
  guard({ on: (name: string, handler: any) => handlers.set(name, handler) } as any);
  const ctx: any = { hasUI, ui: { setStatus: (k: string, v: string) => statuses.set(k, v), notify: (...args: any[]) => notes.push(args) } };
  return { statuses, notes, event: (name: string, data: any = {}) => handlers.get(name)?.(data, ctx) };
}

test("unmanaged Pi blocks every tool, stops the turn, refuses user shell and warns the human", async () => {
  const s = setup();
  await s.event("session_start");
  expect(s.statuses.get("unmanaged-pi")).toContain("UNMANAGED");
  expect(s.notes[0][1]).toBe("error");
  for (const toolName of ["read", "bash", "background_task", "agent_spawn", "ask_user_question"]) {
    expect(await s.event("tool_call", { toolName, input: {} })).toMatchObject({ block: true, terminate: true });
  }
  const shell = await s.event("user_bash", { command: "ls", excludeFromContext: false, cwd: "/" });
  expect(shell.result.exitCode).toBe(1);
  expect(shell.operations).toBeUndefined();
  expect((await s.event("before_agent_start", { systemPrompt: "base" })).systemPrompt).toContain("security boundary");
});

test("is a self-contained single file loadable by the pinned SDK", async () => {
  const source = readFileSync(`${import.meta.dir}/../index.ts`, "utf8");
  expect(source.match(/^import (?!type ).*$/m)).toBeNull();
  const events: any = { emit() {}, on() { return () => {}; } };
  const loaded = await loadExtensions([`${import.meta.dir}/../index.ts`], process.cwd(), events);
  expect(loaded.errors).toEqual([]);
});
