import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { existsSync, linkSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { createServer, type Server } from "node:net";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { linuxSandboxArguments } from "../process.mjs";

const modulePath = fileURLToPath(new URL("../process.mjs", import.meta.url));
const root = realpathSync(mkdtempSync(join(tmpdir(), "pi-sandbox-test-")));
const workspace = join(root, "workspace");
const outside = join(root, "outside");
let socketServer: Server;
let tcpServer: Server;
let tcpPort: number;
const executable = (name: string) => {
  const explicit = process.env[`PI_SANDBOX_${name.toUpperCase()}`];
  const found = explicit || spawnSync("/bin/sh", ["-c", `command -v ${name}`], { encoding: "utf8" }).stdout.trim();
  return found ? realpathSync(found) : "";
};
const node = executable("node");
const bash = executable("bash");
const git = executable("git");
const env = {
  ...process.env,
  PI_EXECUTION_WORKSPACE: workspace,
  PI_SANDBOX_NODE: node,
  PI_SANDBOX_BASH: bash,
  PI_SANDBOX_GIT: git,
  PI_SANDBOX_PATH: [...new Set([dirname(node), dirname(bash), dirname(git)])].join(":"),
  SANDBOX_TEST_SECRET: "must-not-inherit",
  BASH_ENV: join(outside, "startup"),
  NODE_OPTIONS: "",
};
function host(source: string, overrides: Record<string, string> = {}) {
  return spawnSync(node, ["--input-type=module", "-e", `import * as p from ${JSON.stringify(modulePath)}; ${source}`], {
    cwd: workspace, env: { ...env, ...overrides }, encoding: "utf8", timeout: 30000,
  });
}
function run(source: string, readOnly = false) {
  const result = host(`
    import {spawnSync} from 'node:child_process';
    const plan = p.sandboxPlan({executable:p.trustedExecutable('node'),args:['-e',${JSON.stringify(source)}],cwd:process.cwd(),readOnly:${readOnly}});
    try {
      const result = spawnSync(plan.command,plan.args,{...plan.options,encoding:'utf8',timeout:10000});
      console.log(JSON.stringify({status:result.status,stdout:result.stdout,stderr:result.stderr,error:result.error?.message}));
    } finally { plan.cleanup(); }
  `);
  if (result.status !== 0) throw new Error(`Planner failed: ${result.stderr}`);
  return JSON.parse(result.stdout);
}

beforeAll(async () => {
  mkdirSync(workspace); mkdirSync(outside);
  writeFileSync(join(outside, "sentinel"), "private-host-sentinel");
  writeFileSync(join(outside, "startup"), "exit 91\n");
  writeFileSync(join(workspace, "ordinary"), "workspace-data");
  mkdirSync(join(workspace, ".git"));
  writeFileSync(join(workspace, ".git", "config"), "protected-git");
  writeFileSync(join(workspace, "AGENTS.md"), "protected-instructions");
  writeFileSync(join(workspace, ".env.local"), "private-workspace-sentinel");
  symlinkSync(join(outside, "sentinel"), join(workspace, "escape"));
  socketServer = createServer(socket => socket.destroy());
  tcpServer = createServer(socket => socket.destroy());
  await Promise.all([
    new Promise<void>(resolve => socketServer.listen(join(outside, "host.sock"), resolve)),
    new Promise<void>(resolve => tcpServer.listen(0, "127.0.0.1", resolve)),
  ]);
  tcpPort = (tcpServer.address() as { port: number }).port;
  // The socket stays outside the workspace: workspace special files are refused.
});
afterAll(async () => {
  await Promise.all([socketServer, tcpServer].map(server => new Promise<void>(resolve => server.close(() => resolve()))));
  rmSync(root, { recursive: true, force: true });
});

describe("sandbox planner", () => {
  test("captures scope and pinned executables once", () => {
    const result = host(`
      process.env.PI_SANDBOX_NODE='/bin/sh'; process.env.PI_EXECUTION_WORKSPACE='/';
      console.log(JSON.stringify([p.executionWorkspace(),p.trustedExecutable('node')]));
    `);
    expect(result.status).toBe(0);
    expect(JSON.parse(result.stdout)).toEqual([workspace, node]);
  });
  test("requires a pinned executable with no process.execPath fallback", () => {
    const result = host(`p.trustedExecutable('node');`, { PI_SANDBOX_NODE: "" });
    expect(result.status).not.toBe(0);
    expect(result.stderr).toContain("pinned /nix/store");
  });
  test("refuses widening scope and escaping cwd", () => {
    for (const options of [{ cwd: outside }, { cwd: root, workspace: root }]) {
      const result = host(`p.sandboxPlan({executable:p.trustedExecutable('node'),...${JSON.stringify(options)}});`);
      expect(result.status).not.toBe(0);
      expect(result.stderr).toContain("escapes the original");
    }
  });
  test("rejects preexisting hardlink aliases", () => {
    const path = join(workspace, "hardlink");
    linkSync(join(outside, "sentinel"), path);
    try {
      const result = host(`p.executionPlan({command:'true',cwd:process.cwd()});`);
      expect(result.status).not.toBe(0);
      expect(result.stderr).toContain("Hardlinked workspace");
    } finally { rmSync(path); }
  });
  test("rejects special workspace files", () => {
    const path = join(workspace, "fifo");
    expect(spawnSync("/usr/bin/mkfifo", [path]).status).toBe(0);
    try {
      const result = host(`p.executionPlan({command:'true',cwd:process.cwd()});`);
      expect(result.status).not.toBe(0);
      expect(result.stderr).toContain("Special workspace");
    } finally { rmSync(path); }
  });
  test("Linux argv isolates namespaces and masks protected existing paths", () => {
    const args = linuxSandboxArguments({
      executable: "/nix/store/node/bin/node", args: ["-e", "code"], cwd: "/workspace", workspace: "/workspace", scratch: "/scratch",
      env: { PATH: "/nix/store/tools/bin", HOME: "/tmp/home" }, readOnly: false,
      bash: "/nix/store/bash/bin/bash", envExecutable: "/nix/store/coreutils/bin/env",
      protectedPaths: ["/workspace/.git"], secrets: [{ path: "/workspace/.env", directory: false }, { path: "/workspace/.ssh", directory: true }],
    });
    expect(args.slice(0, 9)).toEqual(["--die-with-parent", "--new-session", "--unshare-all", "--cap-drop", "ALL", "--clearenv", "--ro-bind", "/nix/store", "/nix/store"]);
    expect(args).not.toContain("--share-net");
    expect(args.join(" ")).toContain("--symlink /nix/store/bash/bin/bash /bin/sh");
    expect(args.join(" ")).toContain("--symlink /nix/store/coreutils/bin/env /usr/bin/env");
    expect(args).not.toContain("--ro-bind-try");
    expect(args.join(" ")).toContain("--ro-bind /workspace/.git /workspace/.git");
    expect(args.join(" ")).toContain("--ro-bind /scratch/empty /workspace/.env");
    expect(args.join(" ")).toContain("--tmpfs /workspace/.ssh --remount-ro /workspace/.ssh");
    expect(args.slice(-6)).toEqual(["--chdir", "/workspace", "--", "/nix/store/node/bin/node", "-e", "code"]);
  });
});

describe.skipIf(process.platform !== "darwin")("live Darwin Seatbelt", () => {
  test("allows ordinary operations/private scratch and strips host environment", () => {
    const result = run(`
      const fs=require('fs'),path=require('path');
      if(fs.readFileSync('ordinary','utf8')!=='workspace-data') throw Error('read');
      if(fs.realpathSync(process.cwd())!==process.cwd()) throw Error('canonical cwd');
      fs.realpathSync(process.execPath); fs.realpathSync(process.env.TMPDIR);
      fs.writeFileSync('created','ok'); fs.renameSync('created','renamed'); fs.unlinkSync('renamed');
      fs.mkdirSync('nested'); fs.rmdirSync('nested');
      fs.writeFileSync(path.join(process.env.TMPDIR,'scratch'),'ok');
      if(process.env.SANDBOX_TEST_SECRET || process.env.BASH_ENV || process.env.NODE_OPTIONS || process.env.SSH_AUTH_SOCK) throw Error('environment leak');
      if(!process.env.PI_SANDBOX_GIT.startsWith('/nix/store/')) throw Error('missing pinned git');
      console.log('ok');
    `);
    expect(result).toMatchObject({ status: 0, stdout: "ok\n" });
  });
  test("denies host reads/writes and symlink escapes", () => {
    const result = run(`
      const fs=require('fs');
      const denied=fn=>{try{fn()}catch{return}throw Error('unexpected access')};
      denied(()=>fs.readFileSync(${JSON.stringify(join(outside, "sentinel"))}));
      denied(()=>fs.readdirSync(${JSON.stringify(root)}));
      denied(()=>fs.writeFileSync(${JSON.stringify(join(outside, "new"))},'bad'));
      denied(()=>fs.readFileSync('escape'));
      denied(()=>fs.writeFileSync('escape','bad'));
      fs.symlinkSync(${JSON.stringify(join(outside, "sentinel"))},'new-escape');
      denied(()=>fs.readFileSync('new-escape')); fs.unlinkSync('new-escape');
      console.log('denied');
    `);
    expect(result).toMatchObject({ status: 0, stdout: "denied\n" });
    expect(readFileSync(join(outside, "sentinel"), "utf8")).toBe("private-host-sentinel");
    expect(existsSync(join(outside, "new"))).toBe(false);
  });
  test("protects controls and credential names, including newly created names", () => {
    const result = run(`
      const fs=require('fs'); const denied=fn=>{try{fn()}catch{return}throw Error('unexpected access')};
      for(const path of ['.git/config','AGENTS.md','.pi/new.js','nested/.agents/x']) denied(()=>fs.writeFileSync(path,'bad'));
      denied(()=>fs.renameSync('.git','renamed-git'));
      denied(()=>fs.unlinkSync('AGENTS.md'));
      denied(()=>fs.readFileSync('.env.local'));
      denied(()=>fs.readFileSync('.ENV.LOCAL'));
      denied(()=>fs.writeFileSync('.GIT/config','bad'));
      denied(()=>fs.writeFileSync('.env.new','bad'));
      denied(()=>fs.linkSync('.env.local','alias'));
      console.log('denied');
    `);
    expect(result).toMatchObject({ status: 0, stdout: "denied\n" });
    expect(readFileSync(join(workspace, "AGENTS.md"), "utf8")).toBe("protected-instructions");
  });
  test("read-only mode denies workspace writes", () => {
    const result = run(`const fs=require('fs');try{fs.writeFileSync('readonly-write','bad');process.exit(91)}catch{console.log('denied')}`, true);
    expect(result).toMatchObject({ status: 0, stdout: "denied\n" });
  });
  test("denies TCP and Unix sockets", () => {
    const result = run(`
      const net=require('net');
      Promise.all([{host:'127.0.0.1',port:${tcpPort}},{path:${JSON.stringify(join(outside, "host.sock"))}}].map(options=>new Promise((resolve,reject)=>{
        const s=net.connect(options); s.on('connect',()=>reject(Error('network allowed'))); s.on('error',e=>['EPERM','EACCES'].includes(e.code)?resolve():reject(e));
      }))).then(()=>console.log('denied')).catch(e=>{console.error(e);process.exitCode=1});
    `);
    expect(result).toMatchObject({ status: 0, stdout: "denied\n" });
  });
  test("descendants inherit confinement", () => {
    const child = `const fs=require('fs');try{fs.readFileSync(${JSON.stringify(join(outside, "sentinel"))});process.exit(91)}catch{console.log('inherited')}`;
    const result = run(`const cp=require('child_process');const r=cp.spawnSync(process.execPath,['-e',${JSON.stringify(child)}],{encoding:'utf8'});process.stdout.write(r.stdout);process.stderr.write(r.stderr);process.exit(r.status ?? 92)`);
    expect(result).toMatchObject({ status: 0, stdout: "inherited\n" });
  });
});
