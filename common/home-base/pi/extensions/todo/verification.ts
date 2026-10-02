import { spawn } from "node:child_process";
import { realpath } from "node:fs/promises";
import { createHash } from "node:crypto";
import { executionPlan, processPlan, executable } from "../local-process.mjs";
import { FINGERPRINT_SCRIPT } from "./fingerprint.mjs";
import type { Check, State, Todo } from "./model.js";

export interface RunResult {
  exitCode: number | null;
  signal: string | null;
  timedOut: boolean;
  aborted: boolean;
  overflow: boolean;
  output: string;
  error?: string;
}

interface Plan {
  command: string;
  args: string[];
  options: { cwd: string; env: NodeJS.ProcessEnv };
  cleanup?: () => void;
}

/** Bounded local process-group wait and output capture. */
export async function runPlan(plan: Plan, signal?: AbortSignal, timeoutMs = 120_000): Promise<RunResult> {
  const result: RunResult = { exitCode: null, signal: null, timedOut: false, aborted: false, overflow: false, output: "" };
  try {
    signal?.throwIfAborted();
    return await new Promise(resolve => {
      const chunks: Buffer[] = [];
      let bytes = 0;
      let settled = false;
      const child = spawn(plan.command, plan.args, { ...plan.options, detached: true, stdio: ["ignore", "pipe", "pipe"] });
      const kill = () => {
        if (!child.pid) return;
        try { process.kill(-child.pid, "SIGKILL"); } catch { try { child.kill("SIGKILL"); } catch {} }
      };
      const finish = () => {
        if (settled) return;
        settled = true;
        kill();
        clearTimeout(timer);
        clearTimeout(reap);
        signal?.removeEventListener("abort", abort);
        child.stdout.destroy();
        child.stderr.destroy();
        result.output = Buffer.concat(chunks).toString("utf8");
        resolve(result);
      };
      let reap: ReturnType<typeof setTimeout> | undefined;
      const stop = () => { kill(); reap ??= setTimeout(finish, 1000); };
      const abort = () => { result.aborted = true; stop(); };
      const timer = setTimeout(() => { result.timedOut = true; stop(); }, timeoutMs);
      const data = (chunk: Buffer) => {
        if (settled) return;
        const remaining = 10 * 1024 * 1024 - bytes;
        if (remaining > 0) { chunks.push(chunk.subarray(0, remaining)); bytes += Math.min(chunk.length, remaining); }
        if (chunk.length > remaining) { result.overflow = true; stop(); }
      };
      child.stdout.on("data", data);
      child.stderr.on("data", data);
      child.on("error", error => { result.error = error.message; finish(); });
      child.on("close", (code, exitSignal) => { result.exitCode = code; result.signal = exitSignal; finish(); });
      signal?.addEventListener("abort", abort, { once: true });
      if (signal?.aborted) abort();
    });
  } finally { plan.cleanup?.(); }
}

export const successful = (result: RunResult) => result.exitCode === 0 && !result.signal && !result.timedOut && !result.aborted && !result.overflow && !result.error;
export const excerpt = (output: string) => {
  const tail = Buffer.from(output).subarray(-12_000).toString("utf8").split("\n").slice(-200).join("\n");
  return tail === output ? output : `[output truncated; last 12KB/200 lines]\n${tail}`;
};

export async function worktreeFingerprint(cwd: string, signal?: AbortSignal): Promise<string> {
  const result = await runPlan(processPlan({ executable: executable("node"), args: ["-e", FINGERPRINT_SCRIPT], cwd }), signal, 30_000);
  if (!successful(result) || !/^[a-f0-9]{64}$/.test(result.output)) {
    throw new Error(`Cannot fingerprint worktree: ${result.error || excerpt(result.output) || "process failure"}`);
  }
  return result.output;
}

export interface Evidence {
  taskId: number;
  cwd: string;
  fingerprint: string;
  checksDigest: string;
  passed: boolean;
  recordedAt: string;
  finishedAt?: string;
  runs: Array<{ name: string; command: string; startedAt: string; finishedAt: string; durationMs: number; result: RunResult }>;
  reason?: string;
}

export function formatEvidence(evidence: Evidence): string {
  const summary = evidence.runs.map(run => `${run.name}: exit=${run.result.exitCode}, signal=${run.result.signal}, timeout=${run.result.timedOut}, aborted=${run.result.aborted}, overflow=${run.result.overflow}, duration=${Math.round(run.durationMs)}ms${run.result.error ? `, error=${run.result.error}` : ""}`).join("\n");
  const logs = excerpt(evidence.runs.map(run => `[${run.name}]\n${run.result.output}`).join("\n"));
  return `${evidence.recordedAt} → ${evidence.finishedAt ?? "unfinished"}\n${summary}\n${logs}`;
}

export interface Backend {
  fingerprint(cwd: string, signal?: AbortSignal): Promise<string>;
  run(command: string, cwd: string, signal?: AbortSignal): Promise<RunResult>;
}

const digest = (checks: Check[]) => createHash("sha256").update(JSON.stringify(checks)).digest("hex");

/** Only this live object can mint evidence. Restored snapshots never grant completion. */
export class VerificationGate {
  private evidence = new Map<number, Evidence>();
  private generation = 0;
  constructor(private backend: Backend = {
    fingerprint: worktreeFingerprint,
    run: (command, cwd, signal) => runPlan(executionPlan({ command, cwd }), signal),
  }) {}

  reset() { this.generation++; this.evidence.clear(); }
  forget(id: number) { this.evidence.delete(id); }
  details(id: number) { return structuredClone(this.evidence.get(id)); }

  async current(state: State, cwd: string, signal?: AbortSignal): Promise<Set<number>> {
    const relevant = state.todos.filter(todo => todo.checks && this.evidence.has(todo.id));
    const valid = new Set<number>();
    if (!relevant.length) return valid;
    const generation = this.generation;
    let current: string;
    try {
      cwd = await realpath(cwd);
      current = await this.backend.fingerprint(cwd, signal);
      signal?.throwIfAborted();
    } catch { this.reset(); return valid; }
    if (generation !== this.generation) return valid;
    for (const todo of relevant) {
      const evidence = this.evidence.get(todo.id);
      if (evidence?.passed && todo.declaration?.cwd === cwd && evidence.cwd === cwd && evidence.fingerprint === current && evidence.checksDigest === digest(todo.checks!)) valid.add(todo.id);
      else this.evidence.delete(todo.id);
    }
    return valid;
  }

  async verify(todo: Todo, cwd: string, signal?: AbortSignal, update?: (text: string) => void): Promise<Evidence> {
    if (!todo.checks) throw new Error("Only tasks with declared checks can be verified");
    this.forget(todo.id);
    cwd = await realpath(cwd);
    if (!todo.declaration || todo.declaration.cwd !== cwd) throw new Error("Checks lack declaration approval for this canonical working directory; verification is blocked");
    const generation = this.generation;
    const evidence: Evidence = {
      taskId: todo.id, cwd, fingerprint: "", checksDigest: digest(todo.checks),
      passed: false, recordedAt: new Date().toISOString(), runs: [],
    };
    try {
      signal?.throwIfAborted();
      const before = await this.backend.fingerprint(cwd, signal);
      evidence.fingerprint = before;
      for (const check of todo.checks) {
        signal?.throwIfAborted();
        update?.(`Verifying #${todo.id}: ${check.name}`);
        const startedAt = new Date().toISOString();
        const start = performance.now();
        let result: RunResult;
        try { result = await this.backend.run(check.command, cwd, signal); }
        catch (error) { result = { exitCode: null, signal: null, timedOut: false, aborted: signal?.aborted ?? false, overflow: false, output: "", error: error instanceof Error ? error.message : String(error) }; }
        evidence.runs.push({ ...check, startedAt, finishedAt: new Date().toISOString(), durationMs: Math.max(0, performance.now() - start), result: { ...result, output: excerpt(result.output) } });
        if (!successful(result)) { evidence.reason = `Check failed: ${check.name}`; break; }
      }
      signal?.throwIfAborted();
      const after = await this.backend.fingerprint(cwd, signal);
      signal?.throwIfAborted();
      if (generation !== this.generation) throw new Error("Verification lifecycle changed");
      if (after !== before) evidence.reason = "Worktree changed during verification; rerun checks after edits stop";
      evidence.passed = !evidence.reason && evidence.runs.length === todo.checks.length;
    } catch (error) { evidence.reason = error instanceof Error ? error.message : String(error); }
    evidence.finishedAt = new Date().toISOString();
    if (generation === this.generation) this.evidence.set(todo.id, structuredClone(evidence));
    return evidence;
  }
}

/** Reopen all transitive dependents before validating the original dependency graph. */
export function invalidateGated(state: State, valid: ReadonlySet<number>): State {
  const next = structuredClone(state);
  const invalid = new Set(next.todos.filter(todo => todo.checks && !valid.has(todo.id)).map(todo => todo.id));
  let changed = true;
  while (changed) {
    changed = false;
    for (const todo of next.todos) {
      if (!invalid.has(todo.id) && todo.blockedBy.some(id => invalid.has(id))) { invalid.add(todo.id); changed = true; }
    }
  }
  for (const todo of next.todos) {
    if (invalid.has(todo.id) && (todo.status === "completed" || todo.blockedBy.some(id => invalid.has(id)))) todo.status = "pending";
  }
  return next;
}
