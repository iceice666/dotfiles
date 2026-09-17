import { spawn, type ChildProcess } from "node:child_process";
import { randomUUID } from "node:crypto";
import { closeSync, mkdtempSync, openSync, statSync, unlinkSync, writeSync } from "node:fs";
import { tmpdir } from "node:os";
import { isAbsolute, join } from "node:path";

export type TaskStatus = "running" | "stopping" | "completed" | "failed" | "stopped" | "timed_out";
export interface TaskInfo {
  id: string;
  command: string;
  cwd: string;
  status: TaskStatus;
  pid?: number;
  exitCode?: number | null;
  signal?: string | null;
  logPath: string;
  startedAt: string;
  endedAt?: string;
  error?: string;
}
interface RecordState {
  info: TaskInfo;
  child: ChildProcess;
  fd?: number;
  tail: Buffer;
  bytes: number;
  tailTruncated: boolean;
  logTruncated: boolean;
  timeout?: ReturnType<typeof setTimeout>;
  killTimer?: ReturnType<typeof setTimeout>;
  reason?: "stopped" | "timed_out";
  finished: boolean;
  done: Promise<void>;
  resolve: () => void;
}
const TAIL_LIMIT = 1024 * 1024;
const LOG_LIMIT = 10 * 1024 * 1024;
const ACTIVE_LIMIT = 8;
const HISTORY_LIMIT = 100;

/** In-memory task registry. Output is a 1 MiB tail; log files contain at most 10 MiB.
 * output() explicitly reports either truncation. Logs persist after shutdown and
 * history eviction for debugging. Descendants escaping the process group are
 * unsupported; their pipes are disconnected so they cannot block cleanup.
 */
export class TaskManager {
  private records = new Map<string, RecordState>();
  private directory?: string;
  private closing = false;
  private shutdownPromise?: Promise<void>;

  constructor(private readonly onFinish?: (task: TaskInfo) => void) {}

  start(options: { command: string; cwd: string; timeout?: number }): TaskInfo {
    if (this.closing) throw new Error("Task manager is shut down");
    if (process.platform === "win32") throw new Error("Background tasks require macOS or Linux");
    if (!options || typeof options.command !== "string" || !options.command.trim() || options.command.length > 16000 || options.command.includes("\0")) {
      throw new Error("command must be a nonempty string of at most 16000 characters without NUL characters");
    }
    if (typeof options.cwd !== "string" || !isAbsolute(options.cwd) || !statSync(options.cwd).isDirectory()) {
      throw new Error("cwd must be an existing absolute directory");
    }
    if (options.timeout !== undefined && (typeof options.timeout !== "number" || !Number.isFinite(options.timeout) || options.timeout <= 0 || options.timeout * 1000 > 2_147_483_647)) {
      throw new Error("timeout must be positive seconds, at most 2147483.647");
    }
    if ([...this.records.values()].filter((r) => !r.finished).length >= ACTIVE_LIMIT) {
      throw new Error("At most 8 background tasks may be active");
    }
    if (this.records.size >= HISTORY_LIMIT) {
      const oldest = [...this.records.values()].find((r) => r.finished);
      if (oldest) {
        this.records.delete(oldest.info.id);
      }
    }
    if (!this.directory) this.directory = mkdtempSync(join(tmpdir(), "pi-background-"));
    const id = randomUUID();
    const logPath = join(this.directory, `${id}.log`);
    const fd = openSync(logPath, "wx", 0o600);
    let child: ChildProcess;
    try {
      child = spawn("bash", ["-c", options.command], {
        cwd: options.cwd,
        detached: process.platform !== "win32",
        stdio: ["ignore", "pipe", "pipe"],
      });
    } catch (error) {
      closeSync(fd);
      unlinkSync(logPath);
      throw error;
    }
    let resolve!: () => void;
    const done = new Promise<void>((complete) => { resolve = complete; });
    const record: RecordState = {
      info: { id, command: options.command, cwd: options.cwd, status: "running", pid: child.pid, logPath, startedAt: new Date().toISOString() },
      child, fd, tail: Buffer.alloc(0), bytes: 0, tailTruncated: false, logTruncated: false,
      finished: false, done, resolve,
    };
    this.records.set(id, record);
    child.stdout!.on("data", (data: Buffer) => this.append(record, data));
    child.stderr!.on("data", (data: Buffer) => this.append(record, data));
    child.on("error", (error) => { record.info.error = error.message; });
    child.on("exit", (code, signal) => {
      clearTimeout(record.timeout);
      record.info.exitCode = code;
      record.info.signal = signal;
      // A shell can exit while descendants still own stdout/stderr. Never leave
      // such a process group alive waiting for the pipe's close event.
      if (!record.reason) {
        this.signal(record, "SIGKILL");
        record.killTimer = setTimeout(() => this.disconnectAndFinish(record), 500);
      }
    });
    child.on("close", (code, signal) => {
      record.info.exitCode = code;
      record.info.signal = signal;
      if (!record.reason || !record.killTimer) this.finish(record);
    });
    if (options.timeout !== undefined) {
      record.timeout = setTimeout(() => this.requestStop(record, "timed_out"), options.timeout * 1000);
    }
    return { ...record.info };
  }

  list(): TaskInfo[] { return [...this.records.values()].map((r) => ({ ...r.info })); }
  get(id: string): TaskInfo { return { ...this.lookup(id).info }; }

  output(id: string, lines = 200): string {
    if (!Number.isSafeInteger(lines) || lines <= 0) throw new Error("lines must be a positive safe integer");
    const record = this.lookup(id);
    const text = record.tail.toString("utf8");
    const parts = text.split("\n");
    if (parts.at(-1) === "") parts.pop();
    const notices: string[] = [];
    if (record.tailTruncated) notices.push("[Output truncated: showing the retained 1 MiB tail.]");
    if (record.logTruncated) notices.push("[Log truncated: the log file contains only the first 10 MiB.]");
    return [...notices, ...parts.slice(-lines)].join("\n");
  }

  async stop(id: string): Promise<TaskInfo> {
    const record = this.lookup(id);
    this.requestStop(record, "stopped");
    await record.done;
    return { ...record.info };
  }

  shutdown(): Promise<void> {
    if (this.shutdownPromise) return this.shutdownPromise;
    this.closing = true;
    this.shutdownPromise = (async () => {
      const records = [...this.records.values()];
      for (const record of records) this.requestStop(record, "stopped");
      await Promise.all(records.map((r) => r.done));
    })();
    return this.shutdownPromise;
  }

  private lookup(id: string): RecordState {
    const record = this.records.get(id);
    if (!record) throw new Error(`Unknown background task: ${id}`);
    return record;
  }

  private append(record: RecordState, data: Buffer): void {
    if (record.finished) return;
    if (record.tail.length + data.length > TAIL_LIMIT) record.tailTruncated = true;
    record.tail = data.length >= TAIL_LIMIT
      ? Buffer.from(data.subarray(-TAIL_LIMIT))
      : Buffer.concat([record.tail.subarray(Math.max(0, record.tail.length + data.length - TAIL_LIMIT)), data]);
    if (record.bytes + data.length > LOG_LIMIT) record.logTruncated = true;
    const writable = Math.min(data.length, LOG_LIMIT - record.bytes);
    if (writable > 0 && record.fd !== undefined) {
      try {
        let offset = 0;
        while (offset < writable) offset += writeSync(record.fd, data, offset, writable - offset);
        record.bytes += writable;
      } catch (error) {
        record.info.error = `Cannot write task log: ${String(error)}`;
        closeSync(record.fd);
        record.fd = undefined;
        this.requestStop(record, "stopped");
      }
    }
  }

  private signal(record: RecordState, signal: NodeJS.Signals): void {
    if (!record.child.pid) return;
    try {
      if (process.platform !== "win32") process.kill(-record.child.pid, signal);
      else record.child.kill(signal);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ESRCH") record.info.error = `Cannot signal task: ${String(error)}`;
    }
  }

  private requestStop(record: RecordState, reason: "stopped" | "timed_out"): void {
    if (record.finished || record.reason) return;
    record.reason = reason;
    record.info.status = "stopping";
    clearTimeout(record.timeout);
    clearTimeout(record.killTimer);
    this.signal(record, "SIGTERM");
    record.killTimer = setTimeout(() => {
      this.signal(record, "SIGKILL");
      record.killTimer = undefined;
      this.disconnectAndFinish(record);
    }, 500);
  }

  private disconnectAndFinish(record: RecordState): void {
    record.child.stdout?.destroy();
    record.child.stderr?.destroy();
    this.finish(record);
  }

  private finish(record: RecordState): void {
    if (record.finished) return;
    record.finished = true;
    clearTimeout(record.timeout);
    clearTimeout(record.killTimer);
    if (record.fd !== undefined) {
      try { closeSync(record.fd); } catch { /* Best-effort cleanup. */ }
      record.fd = undefined;
    }
    record.info.status = record.reason ?? (record.info.exitCode === 0 && !record.info.error ? "completed" : "failed");
    record.info.endedAt = new Date().toISOString();
    record.resolve();
    if (!this.closing) {
      try { this.onFinish?.({ ...record.info }); } catch { /* Consumer callbacks cannot break cleanup. */ }
    }
  }
}
