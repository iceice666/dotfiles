import { afterEach, describe, expect, test } from "bun:test";
import { existsSync, mkdtempSync, readFileSync, realpathSync, rmSync, statSync, symlinkSync } from "node:fs";
import { getEventListeners } from "node:events";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { TaskManager, type TaskInfo } from "../manager";

const managers: TaskManager[] = [];
const logDirectories = new Set<string>();
function manager(callback?: (task: TaskInfo) => void): TaskManager {
  const instance = new TaskManager(callback);
  managers.push(instance);
  return instance;
}
async function until(predicate: () => boolean, timeout = 5000): Promise<void> {
  const end = Date.now() + timeout;
  while (!predicate()) {
    if (Date.now() >= end) throw new Error("Condition timed out");
    await Bun.sleep(10);
  }
}
async function finish(instance: TaskManager, id: string): Promise<TaskInfo> {
  await until(() => !["running", "stopping"].includes(instance.get(id).status));
  return instance.get(id);
}
function alive(pid: number): boolean {
  try { process.kill(pid, 0); return true; } catch { return false; }
}
afterEach(async () => {
  await Promise.all(managers.splice(0).map(async (instance) => {
    for (const task of instance.list()) logDirectories.add(join(task.logPath, ".."));
    await instance.shutdown();
  }));
  for (const directory of logDirectories) rmSync(directory, { recursive: true, force: true });
  logDirectories.clear();
});

describe("TaskManager", () => {
  test("wait observes completion and failure, including already finished jobs", async () => {
    const instance = manager();
    const task = instance.start({ command: "printf ready; exit 7", cwd: tmpdir() });
    const result = await instance.wait(task.id);
    expect(result.outcome).toBe("finished");
    expect(result.task.status).toBe("failed");
    expect(result.task.exitCode).toBe(7);
    expect(instance.output(task.id)).toBe("ready");
    expect((await instance.wait(task.id)).outcome).toBe("finished");
    result.task.status = "running";
    expect(instance.get(task.id).status).toBe("failed");
  });

  test("wait timeout and abort detach listeners without stopping the job", async () => {
    const instance = manager();
    const task = instance.start({ command: "sleep 30", cwd: tmpdir() });
    const record = (instance as any).records.get(task.id);
    expect((await instance.wait(task.id, { timeout: 0.01 })).outcome).toBe("timed_out");
    expect(record.waiters.size).toBe(0);
    const controller = new AbortController();
    const waiting = instance.wait(task.id, { signal: controller.signal });
    expect(record.waiters.size).toBe(1);
    expect(getEventListeners(controller.signal, "abort")).toHaveLength(1);
    controller.abort();
    expect((await waiting).outcome).toBe("aborted");
    expect(record.waiters.size).toBe(0);
    expect(getEventListeners(controller.signal, "abort")).toHaveLength(0);
    expect((await instance.wait(task.id, { signal: AbortSignal.abort() })).outcome).toBe("aborted");
    expect(record.waiters.size).toBe(0);
    expect(instance.get(task.id).status).toBe("running");
    expect(alive(task.pid!)).toBe(true);
  });

  test("concurrent waiters settle on stop and shutdown and clean subscriptions", async () => {
    const instance = manager();
    const task = instance.start({ command: "sleep 30", cwd: tmpdir() });
    const controller = new AbortController();
    const aborted = instance.wait(task.id, { signal: controller.signal });
    const first = instance.wait(task.id), second = instance.wait(task.id);
    controller.abort();
    await instance.stop(task.id);
    expect((await aborted).outcome).toBe("aborted");
    for (const waiting of [first, second]) {
      expect((await waiting).task.status).toBe("stopped");
      expect((await waiting).outcome).toBe("finished");
    }
    expect((instance as any).records.get(task.id).waiters.size).toBe(0);
    const next = instance.start({ command: "sleep 30", cwd: tmpdir() });
    const waiting = instance.wait(next.id);
    await instance.shutdown();
    expect((await waiting).task.status).toBe("stopped");
    expect((instance as any).records.get(next.id).waiters.size).toBe(0);
  });

  test("wait validates IDs and deadlines without registering listeners", () => {
    const instance = manager();
    expect(() => instance.wait("missing")).toThrow("Unknown");
    const task = instance.start({ command: "sleep 30", cwd: tmpdir() });
    for (const timeout of [0, -1, NaN, Infinity, 86401]) {
      expect(() => instance.wait(task.id, { timeout })).toThrow("timeout");
    }
    expect((instance as any).records.get(task.id).waiters.size).toBe(0);
  });

  test("resolves Bash from PATH instead of assuming /bin/bash", async () => {
    const directory = mkdtempSync(join(tmpdir(), "pi-task-path-"));
    const previousPath = process.env.PATH;
    const executable = Bun.which("bash");
    expect(executable).not.toBeNull();
    symlinkSync(executable!, join(directory, "bash"));
    try {
      process.env.PATH = directory;
      const instance = manager();
      const task = instance.start({ command: 'printf "%s" "$BASH"', cwd: directory });
      process.env.PATH = previousPath;
      expect((await finish(instance, task.id)).status).toBe("completed");
      expect(instance.output(task.id)).toBe(join(directory, "bash"));
    } finally {
      if (previousPath === undefined) delete process.env.PATH;
      else process.env.PATH = previousPath;
      rmSync(directory, { recursive: true, force: true });
    }
  });

  test("captures stdout/stderr, exit codes, tail lines, snapshots, and callbacks", async () => {
    const finished: TaskInfo[] = [];
    const instance = manager((task) => finished.push(task));
    const first = instance.start({ command: "printf 'first\\nsecond\\n'; printf 'error\\n' >&2", cwd: tmpdir() });
    expect(first.status).toBe("running");
    const result = await finish(instance, first.id);
    expect(result.status).toBe("completed");
    expect(result.exitCode).toBe(0);
    expect(result.endedAt).toBeString();
    expect(first.status).toBe("running");
    expect(instance.output(first.id)).toContain("first\nsecond");
    expect(instance.output(first.id)).toContain("error");
    expect(instance.output(first.id, 1).split("\n")).toHaveLength(1);
    expect(readFileSync(result.logPath, "utf8")).toContain("first");
    expect(statSync(result.logPath).mode & 0o777).toBe(0o600);
    expect(statSync(join(result.logPath, "..")).mode & 0o777).toBe(0o700);
    expect(finished).toHaveLength(1);
    result.status = "failed";
    expect(instance.get(first.id).status).toBe("completed");
    const failure = instance.start({ command: "exit 17", cwd: tmpdir() });
    expect((await finish(instance, failure.id)).status).toBe("failed");
    expect(instance.get(failure.id).exitCode).toBe(17);
  });

  test("uses cwd, disconnected stdin, and preserves output without newline", async () => {
    const cwd = mkdtempSync(join(tmpdir(), "pi-task-test-"));
    try {
      const instance = manager();
      const task = instance.start({ command: "pwd; read x || printf 'stdin closed'", cwd });
      await finish(instance, task.id);
      expect(instance.output(task.id)).toBe(`${realpathSync(cwd)}\nstdin closed`);
    } finally { rmSync(cwd, { recursive: true, force: true }); }
  });

  test("timeout and repeated stop preserve terminal reasons", async () => {
    const instance = manager();
    const task = instance.start({ command: "sleep 30", cwd: tmpdir(), timeout: 0.05 });
    const waited = await instance.wait(task.id);
    expect(waited.outcome).toBe("finished");
    expect(waited.task.status).toBe("timed_out");
    expect((await instance.stop(task.id)).status).toBe("timed_out");
    const second = instance.start({ command: "sleep 30", cwd: tmpdir() });
    const [a, b] = await Promise.all([instance.stop(second.id), instance.stop(second.id)]);
    expect(a.status).toBe("stopped");
    expect(b.status).toBe("stopped");
  });

  test("stop kills TERM-resistant descendants even when leader exits", async () => {
    const instance = manager();
    const task = instance.start({ command: "bash -c 'trap \"\" TERM; echo $$; while :; do sleep 1; done' & wait", cwd: tmpdir() });
    await until(() => /^\d+/.test(instance.output(task.id)));
    const pid = Number(instance.output(task.id).split("\n")[0]);
    expect(alive(pid)).toBe(true);
    expect((await instance.stop(task.id)).status).toBe("stopped");
    await until(() => !alive(pid));
  });

  test("leader exiting cleans descendants retaining output pipes", async () => {
    const instance = manager();
    const task = instance.start({ command: "sleep 30 & echo $!; exit 0", cwd: tmpdir() });
    const result = await finish(instance, task.id);
    expect(result.status).toBe("completed");
    const pid = Number(instance.output(task.id));
    expect(pid).toBeGreaterThan(0);
    await until(() => !alive(pid));
  });

  test("shutdown suppresses callbacks, retains logs, and is idempotent", async () => {
    let callbacks = 0;
    const instance = manager(() => callbacks++);
    const task = instance.start({ command: "sleep 30", cwd: tmpdir() });
    await Promise.all([instance.shutdown(), instance.shutdown()]);
    expect(callbacks).toBe(0);
    expect(instance.get(task.id).status).toBe("stopped");
    expect(existsSync(task.logPath)).toBe(true);
    expect(() => instance.start({ command: "true", cwd: tmpdir() })).toThrow("shut down");
  });

  test("bounds tail memory and log disk usage with visible truncation", async () => {
    const instance = manager();
    const task = instance.start({ command: "head -c 11534336 /dev/zero | tr '\\000' x; printf '\\nEND\\n'", cwd: tmpdir() });
    await finish(instance, task.id);
    const output = instance.output(task.id);
    expect(output).toContain("Output truncated");
    expect(output).toContain("Log truncated");
    expect(output.endsWith("END")).toBe(true);
    expect(Buffer.byteLength(output)).toBeLessThan(1024 * 1024 + 200);
    expect(statSync(task.logPath).size).toBe(10 * 1024 * 1024);
  });

  test("validates arguments and limits active tasks", async () => {
    const instance = manager();
    expect(() => instance.get("missing")).toThrow("Unknown");
    expect(() => instance.output("missing")).toThrow("Unknown");
    expect(() => instance.start({ command: " ", cwd: tmpdir() })).toThrow();
    expect(() => instance.start({ command: "x\0", cwd: tmpdir() })).toThrow();
    expect(() => instance.start({ command: "x".repeat(16001), cwd: tmpdir() })).toThrow();
    expect(() => instance.start({ command: "true", cwd: "relative" })).toThrow();
    expect(() => instance.start({ command: "true", cwd: "/this/path/does/not/exist" })).toThrow();
    for (const timeout of [0, -1, NaN, Infinity, 2147484]) {
      expect(() => instance.start({ command: "true", cwd: tmpdir(), timeout })).toThrow();
    }
    for (let i = 0; i < 8; i++) instance.start({ command: "sleep 30", cwd: tmpdir() });
    expect(() => instance.start({ command: "true", cwd: tmpdir() })).toThrow("8");
    for (const lines of [0, -1, 0.5, NaN, Infinity]) {
      expect(() => instance.output(instance.list()[0].id, lines)).toThrow("lines");
    }
  });

  test("evicts old completed history at 100 tasks but retains logs", async () => {
    const instance = manager();
    const first = instance.start({ command: "true", cwd: tmpdir() });
    await finish(instance, first.id);
    for (let i = 0; i < 100; i++) {
      const task = instance.start({ command: "true", cwd: tmpdir() });
      await finish(instance, task.id);
    }
    expect(instance.list()).toHaveLength(100);
    expect(() => instance.get(first.id)).toThrow("Unknown");
    expect(existsSync(first.logPath)).toBe(true);
  });
});
