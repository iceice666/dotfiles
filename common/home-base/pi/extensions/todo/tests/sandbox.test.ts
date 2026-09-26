import { afterAll, describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { mkdtempSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

const root = realpathSync(mkdtempSync(join(tmpdir(), "pi-todo-live-")));
const executable = (name: string) => realpathSync(spawnSync("/bin/sh", ["-c", `command -v ${name}`], { encoding: "utf8" }).stdout.trim());
const node = executable("node"), git = executable("git"), bash = executable("bash");
const env = { ...process.env, PI_EXECUTION_WORKSPACE: root, PI_SANDBOX_NODE: node, PI_SANDBOX_GIT: git,
  PI_SANDBOX_BASH: bash, PI_SANDBOX_PATH: [...new Set([dirname(node), dirname(git), dirname(bash)])].join(":"), NODE_OPTIONS: "" };
const verification = join(import.meta.dir, "../verification.ts");
const planner = join(import.meta.dir, "../../execution-policy/process.mjs");
function run(source: string) {
  const child = spawnSync(process.execPath, ["-e", `import {worktreeFingerprint,runPlan,successful,VerificationGate} from ${JSON.stringify(verification)}; import {executionPlan,sandboxPlan,trustedExecutable} from ${JSON.stringify(planner)}; ${source}`], {
    cwd: root, env, encoding: "utf8", timeout: 30000,
  });
  expect(child.stderr).toBe("");
  expect(child.status).toBe(0);
  return JSON.parse(child.stdout);
}
afterAll(() => rmSync(root, { recursive: true, force: true }));

describe.skipIf(process.platform !== "darwin")("live sandbox verification", () => {
  test("fingerprints empty repos, tracked content, index and edit/revert changes", () => {
    expect(spawnSync(git, ["init", "-q", root]).status).toBe(0);
    writeFileSync(join(root, "source"), "one");
    const hashes = run(`
      import {writeFileSync} from 'node:fs'; import {spawnSync} from 'node:child_process';
      const a=await worktreeFingerprint(process.cwd());
      const stable=await worktreeFingerprint(process.cwd());
      writeFileSync('source','two'); const b=await worktreeFingerprint(process.cwd());
      writeFileSync('source','one'); const c=await worktreeFingerprint(process.cwd());
      const staged=spawnSync(trustedExecutable('git'),['add','source']); if(staged.status!==0)throw Error('git add failed');
      const d=await worktreeFingerprint(process.cwd());
      console.log(JSON.stringify([a,stable,b,c,d]));
    `);
    expect(hashes[0]).toMatch(/^[a-f0-9]{64}$/);
    expect(hashes[1]).toBe(hashes[0]);
    expect(new Set([hashes[0], ...hashes.slice(2)]).size).toBe(4);
  });

  test("actual process status and bounded timeout/abort/output capture", () => {
    const results = run(`
      const plan=code=>sandboxPlan({executable:trustedExecutable('node'),args:['-e',code],cwd:process.cwd()});
      const ok=await runPlan(plan("console.log('actual stdout');console.error('actual stderr')"));
      const failed=await runPlan(plan("process.exit(7)"));
      const timeout=await runPlan(plan("setInterval(()=>{},1000)"),undefined,100);
      const controller=new AbortController(); const timer=setTimeout(()=>controller.abort(),100);
      const aborted=await runPlan(plan("setInterval(()=>{},1000)"),controller.signal); clearTimeout(timer);
      const overflow=await runPlan(plan("process.stdout.write('x'.repeat(11*1024*1024))"));
      console.log(JSON.stringify({ok,failed,timeout,aborted,overflow:{...overflow,outputBytes:Buffer.byteLength(overflow.output),output:''}}));
    `);
    expect(results.ok.exitCode).toBe(0);
    expect(results.ok.output).toContain("actual stdout");
    expect(results.ok.output).toContain("actual stderr");
    expect(results.failed.exitCode).toBe(7);
    expect(results.timeout.timedOut).toBe(true);
    expect(results.aborted.aborted).toBe(true);
    expect(results.overflow.overflow).toBe(true);
    expect(results.overflow.outputBytes).toBeLessThanOrEqual(10 * 1024 * 1024);
  });
});
