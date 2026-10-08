import { afterEach, expect, test } from "bun:test";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { approveAction } from "../approval.ts";
import { Team } from "../../agent-team/team.mjs";

const keys = ["PI_TEAM_AGENT", "PI_TEAM_URL", "PI_TEAM_TOKEN"] as const;
const original = Object.fromEntries(keys.map(key => [key, process.env[key]]));
const reset = () => { for (const key of keys) delete process.env[key]; };
afterEach(() => {
  for (const key of keys) {
    if (original[key] === undefined) delete process.env[key];
    else process.env[key] = original[key];
  }
});
const action = {
  toolName: "todo", cwd: process.cwd(),
  input: { action: "add", items: [{ text: "Verify change", checks: [{ name: "tests", command: "bun test" }] }] },
};
const signal = () => new AbortController().signal;

test("standalone declaration approval displays exact arguments and requires explicit selection", async () => {
  reset();
  let shown = "";
  const ctx: any = { hasUI: true, mode: "rpc", ui: { select: async (title: string, rows: string[]) => {
    shown = title;
    expect(rows[0]).toContain("拒絕");
    return rows[1];
  } } };
  expect(await approveAction(ctx, action, "Declare required checks", signal())).toBe(true);
  expect(shown).toContain(JSON.stringify(action.input, null, 2));
  expect(shown).toContain(action.cwd);
  expect(shown).toContain("Declare required checks");
  expect(shown).not.toContain("Auto Mode");
});

test("refusal, custom text, cancellation, no UI and oversized declarations never approve", async () => {
  reset();
  for (const choice of [0, 2, undefined]) {
    const ctx: any = { hasUI: true, mode: "rpc", ui: {
      select: async (_title: string, rows: string[]) => choice === undefined ? undefined : rows[choice],
      input: async () => "yes",
    } };
    expect(await approveAction(ctx, action, "checks", signal())).toBe(false);
  }
  expect(await approveAction({ hasUI: false } as any, action, "checks", signal())).toBe(false);
  const ctx: any = { hasUI: true, mode: "rpc", ui: { select: () => { throw new Error("Must not prompt"); } } };
  const abort = new AbortController(); abort.abort();
  expect(await approveAction(ctx, action, "checks", abort.signal)).toBe(false);
  expect(await approveAction(ctx, { ...action, input: { text: "x".repeat(13000) } }, "checks", signal())).toBe(false);
});

test("worker declaration approval uses the authenticated broker without a local UI", async () => {
  reset();
  const directory = mkdtempSync(join(tmpdir(), "pi-declaration-approval-"));
  let prompted = 0;
  const team = new Team({ directory, extension: "/unused", deliverParent() {}, askUser: async (question: any) => {
    prompted++;
    expect(question.question).toContain(JSON.stringify(action.input, null, 2));
    return { status: "answered", answers: [{ question: question.question, selected: ["僅允許這次操作"] }] };
  } });
  try {
    await team.ready;
    team.agents.set("worker", { name: "worker", status: "running", rpc: { stop: async () => {} } });
    team.tokens.set("Bearer fixture", "worker");
    process.env.PI_TEAM_AGENT = "worker";
    expect(await approveAction({ hasUI: false } as any, action, "checks", signal())).toBe(false);
    process.env.PI_TEAM_URL = team.url;
    process.env.PI_TEAM_TOKEN = "Bearer fixture";
    expect(await approveAction({ hasUI: false } as any, action, "checks", signal())).toBe(true);
    expect(prompted).toBe(1);
    process.env.PI_TEAM_TOKEN = "Bearer invalid";
    expect(await approveAction({ hasUI: false } as any, action, "checks", signal())).toBe(false);
    expect(prompted).toBe(1);
  } finally {
    await team.close();
    rmSync(directory, { recursive: true, force: true });
  }
});
