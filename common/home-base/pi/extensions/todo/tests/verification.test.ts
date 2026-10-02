import { describe, expect, test } from "bun:test";
import { realpathSync } from "node:fs";
import { applyAction, emptyState, parseState, type Todo } from "../model";
import { VerificationGate, invalidateGated, excerpt, successful, type RunResult } from "../verification";

const cwd = realpathSync(process.cwd());
const ok = (): RunResult => ({ exitCode: 0, signal: null, timedOut: false, aborted: false, overflow: false, output: "actual output" });
const task = (): Todo => ({ id: 1, text: "Test changes", blockedBy: [], status: "pending", checks: [{ name: "unit", command: "bun test" }], declaration: { cwd, approvedAt: new Date().toISOString() } });
const state = () => ({ version: 1 as const, nextId: 2, todos: [task()] });

 describe("completion verification", () => {
  test("only actual successful execution produces fresh, copied evidence", async () => {
    const commands: string[] = [];
    let fingerprint = "one";
    const gate = new VerificationGate({ fingerprint: async () => fingerprint, run: async command => { commands.push(command); return ok(); } });
    const evidence = await gate.verify(task(), cwd);
    expect(commands).toEqual(["bun test"]);
    expect(evidence.passed).toBe(true);
    expect(evidence.runs[0].result.output).toBe("actual output");
    expect(Date.parse(evidence.runs[0].finishedAt)).toBeGreaterThanOrEqual(Date.parse(evidence.runs[0].startedAt));
    expect(evidence.runs[0].durationMs).toBeGreaterThanOrEqual(0);
    evidence.passed = false;
    expect((await gate.current(state(), cwd)).has(1)).toBe(true);
    fingerprint = "two";
    expect((await gate.current(state(), cwd)).size).toBe(0);
    fingerprint = "one";
    expect((await gate.current(state(), cwd)).size).toBe(0);
  });

  test("fails closed on failure, signal, timeout, abort, overflow and launch errors", async () => {
    for (const patch of [{ exitCode: 1 }, { signal: "SIGTERM" }, { timedOut: true }, { aborted: true }, { overflow: true }, { error: "spawn denied" }]) {
      const gate = new VerificationGate({ fingerprint: async () => "one", run: async () => ({ ...ok(), ...patch }) });
      expect((await gate.verify(task(), cwd)).passed).toBe(false);
      expect((await gate.current(state(), cwd)).size).toBe(0);
    }
    const gate = new VerificationGate({ fingerprint: async () => "one", run: async () => { throw new Error("backend unavailable"); } });
    const evidence = await gate.verify(task(), cwd);
    expect(evidence.passed).toBe(false);
    expect(evidence.runs[0].result.error).toBe("backend unavailable");
    expect(evidence.runs[0].result.exitCode).toBeNull();
  });

  test("captures fingerprint failures and changes during checks without certifying", async () => {
    let fingerprint = "one";
    const gate = new VerificationGate({ fingerprint: async () => fingerprint, run: async () => { fingerprint = "two"; return ok(); } });
    const evidence = await gate.verify(task(), cwd);
    expect(evidence.passed).toBe(false);
    expect(evidence.reason).toContain("changed during");
    const unavailable = new VerificationGate({ fingerprint: async () => { throw new Error("fingerprint unavailable"); }, run: async () => ok() });
    const failed = await unavailable.verify(task(), cwd);
    expect(failed.passed).toBe(false);
    expect(failed.runs).toEqual([]);
    expect(failed.reason).toContain("fingerprint unavailable");
  });

  test("approval is cwd-bound; restored history cannot attest and missing approval blocks", async () => {
    let runs = 0;
    const gate = new VerificationGate({ fingerprint: async () => "one", run: async () => { runs++; return ok(); } });
    const unapproved = task();
    delete unapproved.declaration;
    await expect(gate.verify(unapproved, cwd)).rejects.toThrow(/approval/);
    await expect(gate.verify({ ...task(), declaration: { cwd: "/different", approvedAt: new Date().toISOString() } }, cwd)).rejects.toThrow(/approval/);
    expect(runs).toBe(0);
    await gate.verify(task(), cwd);
    gate.reset();
    expect((await gate.current(state(), cwd)).size).toBe(0);
    const persisted = parseState({ ...state(), todos: [{ ...task(), status: "completed", evidence: { passed: true } }] })!;
    expect(invalidateGated(persisted, new Set()).todos[0].status).toBe("pending");
  });

  test("reset and cancellation during verification cannot mint later evidence", async () => {
    const controller = new AbortController();
    const gate = new VerificationGate({ fingerprint: async () => "one", run: async () => { gate.reset(); return ok(); } });
    expect((await gate.verify(task(), cwd)).passed).toBe(false);
    expect(gate.details(1)).toBeUndefined();
    const aborted = new VerificationGate({ fingerprint: async () => "one", run: async () => { controller.abort(); return ok(); } });
    expect((await aborted.verify(task(), cwd, controller.signal)).passed).toBe(false);
    expect((await aborted.current(state(), cwd)).size).toBe(0);
  });

  test("stale gates reopen dependent closure without invalid graphs", () => {
    const source = { version: 1 as const, nextId: 5, todos: [
      { ...task(), status: "completed" as const },
      { id: 2, text: "dependent", status: "completed" as const, blockedBy: [1] },
      { id: 3, text: "transitive", status: "in_progress" as const, blockedBy: [2] },
      { id: 4, text: "unrelated", status: "completed" as const, blockedBy: [] },
    ] };
    const reopened = invalidateGated(source, new Set());
    expect(reopened.todos.map(todo => todo.status)).toEqual(["pending", "pending", "pending", "completed"]);
    expect(parseState(reopened)).toEqual(reopened);
    expect(source.todos[0].status).toBe("completed");
  });

  test("gate requirements cannot be removed, edited or self-certified", () => {
    const source = applyAction(emptyState(), { action: "add", text: "Gate", checks: task().checks });
    for (const action of [
      { action: "update", id: 1, status: "completed" },
      { action: "update", id: 1, text: "Ignore gate" },
      { action: "update", id: 1, checks: [] },
      { action: "remove", id: 1 },
      { action: "clear" },
      { action: "update", id: 1, evidence: { passed: true } },
      { action: "add", text: "Forged", declaration: task().declaration },
    ]) expect(() => applyAction(source, action as any)).toThrow();
    expect(applyAction(source, { action: "prune" })).toEqual(source);
    expect(() => applyAction(emptyState(), { action: "add", text: "Gate", checks: task().checks, status: "completed" })).toThrow();
    const completed = applyAction(source, { action: "update", id: 1, status: "completed" }, new Set([1]));
    expect(() => applyAction(completed, { action: "prune" })).toThrow();
    expect(applyAction(completed, { action: "prune" }, new Set([1])).todos).toEqual([]);
  });

  test("bounds check declarations and captured output", () => {
    for (const checks of [[], Array(11).fill({ name: "x", command: "true" }), [{ name: "x", command: "" }], [{ name: "x", command: "a\nb" }], [{ name: "x", command: "true", evidence: true }]]) {
      expect(() => applyAction(emptyState(), { action: "add", text: "Gate", checks })).toThrow();
    }
    const output = excerpt("中".repeat(10000));
    expect(Buffer.byteLength(output)).toBeLessThan(12100);
    expect(output).toContain("truncated");
    expect(excerpt("line\n".repeat(1000)).split("\n").length).toBeLessThanOrEqual(201);
    expect(successful(ok())).toBe(true);
  });
});
