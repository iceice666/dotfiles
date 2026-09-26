import { spawn } from "node:child_process";
import { executionPlan, sandboxPlan, trustedExecutable } from "./process.mjs";
import { canonicalPath } from "../auto-mode/policy.ts";

export interface Plan {
  command: string;
  args: string[];
  options: { cwd: string; env: NodeJS.ProcessEnv };
  cleanup?: () => void;
}

/** Trusted host transport; only the OS-confined child touches agent-selected files. */
export function runPlan(plan: Plan, options: {
  input?: string;
  signal?: AbortSignal;
  timeout?: number;
  maxBytes?: number;
  onData?: (data: Buffer) => void;
} = {}): Promise<{ output: Buffer; exitCode: number | null }> {
  return new Promise((resolve, reject) => {
    let child: ReturnType<typeof spawn>;
    try {
      options.signal?.throwIfAborted();
      child = spawn(plan.command, plan.args, { ...plan.options, detached: true, stdio: ["pipe", "pipe", "pipe"] });
    } catch (error) { plan.cleanup?.(); reject(error); return; }
    const buffers: Buffer[] = [];
    let bytes = 0;
    let failure: Error | undefined;
    let done = false;
    let killTimer: ReturnType<typeof setTimeout> | undefined;
    const kill = () => {
      if (child.pid) try { process.kill(-child.pid, "SIGKILL"); } catch { /* Already exited. */ }
    };
    const finish = (code: number | null) => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      clearTimeout(killTimer);
      options.signal?.removeEventListener("abort", abort);
      kill();
      child.stdin?.destroy(); child.stdout?.destroy(); child.stderr?.destroy();
      plan.cleanup?.();
      if (failure) reject(failure);
      else resolve({ output: Buffer.concat(buffers), exitCode: code });
    };
    const stop = (error: Error) => {
      failure ??= error;
      kill();
      killTimer ??= setTimeout(() => finish(null), 500);
    };
    const abort = () => stop(new Error("Restricted operation cancelled."));
    const timer = setTimeout(() => stop(new Error("Restricted operation timed out.")), (options.timeout ?? 120) * 1000);
    options.signal?.addEventListener("abort", abort, { once: true });
    if (options.signal?.aborted) abort();
    const data = (chunk: Buffer) => {
      if (done) return;
      if (options.onData) options.onData(chunk);
      else {
        bytes += chunk.length;
        if (bytes > (options.maxBytes ?? 32 * 1024 * 1024)) { stop(new Error("Restricted operation exceeded its output limit.")); return; }
        buffers.push(chunk);
      }
    };
    child.stdout!.on("data", data);
    child.stderr!.on("data", data);
    child.on("error", () => stop(new Error("Cannot start the required sandbox backend; no unsandboxed fallback.")));
    child.on("exit", code => {
      kill();
      // An escaped descendant must not hold the transport open indefinitely.
      killTimer ??= setTimeout(() => finish(code), 500);
    });
    child.on("close", code => finish(code));
    child.stdin!.on("error", () => { /* EPIPE is reported by the child's exit status. */ });
    child.stdin!.end(options.input);
  });
}

const FILE_HELPER = `
const fs = require('node:fs');
(async () => {
  let raw = ''; for await (const b of process.stdin) { raw += b; if (raw.length > 24*1024*1024) throw Error('Input too large'); }
  const {op,path,content} = JSON.parse(raw);
  let result;
  switch (op) {
    case 'read': {
      const fd = fs.openSync(path, fs.constants.O_RDONLY | fs.constants.O_NONBLOCK);
      try {
        const stat = fs.fstatSync(fd);
        if (!stat.isFile() || stat.size > 16*1024*1024) throw Error('Expected regular file at most 16 MiB');
        const buffer = Buffer.alloc(16*1024*1024+1);
        let size = 0, count;
        while (size < buffer.length && (count = fs.readSync(fd, buffer, size, buffer.length-size, null))) size += count;
        if (size > 16*1024*1024) throw Error('File exceeds 16 MiB');
        result = buffer.subarray(0,size).toString('base64');
      } finally { fs.closeSync(fd); }
      break;
    }
    case 'access': fs.accessSync(path, fs.constants.R_OK); result = true; break;
    case 'write': {
      const fd = fs.openSync(path, fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_NONBLOCK, 0o600);
      try {
        if (!fs.fstatSync(fd).isFile()) throw Error('Expected regular file');
        fs.ftruncateSync(fd); fs.writeFileSync(fd, content);
      } finally { fs.closeSync(fd); }
      result = true; break;
    }
    case 'mkdir': fs.mkdirSync(path, {recursive:true}); result = true; break;
    case 'exists': result = fs.existsSync(path); break;
    case 'stat': result = {directory:fs.statSync(path).isDirectory()}; break;
    case 'readdir': result = fs.readdirSync(path); break;
    default: throw Error('Unknown operation');
  }
  process.stdout.write(JSON.stringify({result}));
})().catch(e => { process.stderr.write(String(e.message)); process.exitCode = 1; });
`;

export async function fileOperation(op: string, path: string, cwd: string, workspace: string, signal?: AbortSignal, content?: string): Promise<any> {
  path = canonicalPath(path, cwd);
  const plan = sandboxPlan({ executable: trustedExecutable("node"), args: ["-e", FILE_HELPER], cwd, workspace, readOnly: !["write", "mkdir"].includes(op) });
  const result = await runPlan(plan, { input: JSON.stringify({ op, path, content }), signal, timeout: 30 });
  if (result.exitCode !== 0) throw new Error(`Restricted file operation failed: ${result.output.toString("utf8").slice(0, 2000)}`);
  return JSON.parse(result.output.toString("utf8")).result;
}

export async function sandboxRead(path: string, cwd: string, workspace: string, signal?: AbortSignal): Promise<Buffer> {
  return Buffer.from(await fileOperation("read", path, cwd, workspace, signal), "base64");
}

export function shellOperations(workspace: string) {
  return {
    async exec(command: string, cwd: string, options: { onData: (data: Buffer) => void; signal?: AbortSignal; timeout?: number }) {
      if (options.timeout !== undefined && (!Number.isFinite(options.timeout) || options.timeout <= 0 || options.timeout > 86400)) throw new Error("Timeout must be 1–86400 seconds.");
      return runPlan(executionPlan({ command, cwd, workspace }), { ...options, timeout: options.timeout ?? 120 });
    },
  };
}
