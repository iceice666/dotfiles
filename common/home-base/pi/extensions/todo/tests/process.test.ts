import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { mkdtempSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const root = realpathSync(mkdtempSync(join(tmpdir(), "pi-todo-live-")));
const tool = (name: string) => {
  const found = Bun.which(name);
  if (!found) throw new Error(`Test requires ${name} on PATH`);
  return realpathSync(found);
};
const node = tool("node"), git = tool("git"), bash = tool("bash");
// Synthetic environment: tests never consume user credentials or make network calls.
const env = { PATH: process.env.PATH, HOME: root, TMPDIR: root, LC_ALL: "C",
  PI_TOOL_NODE: node, PI_TOOL_GIT: git, PI_TOOL_BASH: bash };
const verification = join(import.meta.dir, "../verification.ts");
const planner = join(import.meta.dir, "../../local-process.mjs");
function run(source: string, overrides: NodeJS.ProcessEnv = {}) {
  const child = spawnSync(process.execPath, ["-e", `import {worktreeFingerprint,runPlan,successful,VerificationGate} from ${JSON.stringify(verification)}; import {executionPlan,processPlan,executable} from ${JSON.stringify(planner)}; ${source}`], {
    cwd: root, env: { ...env, ...overrides }, encoding: "utf8", timeout: 30000,
  });
  expect(child.stderr).toBe("");
  expect(child.status).toBe(0);
  return JSON.parse(child.stdout);
}
beforeAll(() => expect(spawnSync(git, ["init", "-q", root], { env }).status).toBe(0));
afterAll(() => rmSync(root, { recursive: true, force: true }));

describe("local process verification (macOS/Linux)", () => {
  test("fingerprints empty repos, tracked content, index and edit/revert changes", () => {
    writeFileSync(join(root, "source"), "one");
    const hashes = run(`
      import {writeFileSync} from 'node:fs'; import {spawnSync} from 'node:child_process';
      const a=await worktreeFingerprint(process.cwd());
      const stable=await worktreeFingerprint(process.cwd());
      writeFileSync('source','two'); const b=await worktreeFingerprint(process.cwd());
      writeFileSync('source','one'); const c=await worktreeFingerprint(process.cwd());
      const staged=spawnSync(executable('git'),['add','source']); if(staged.status!==0)throw Error('git add failed');
      const d=await worktreeFingerprint(process.cwd());
      console.log(JSON.stringify([a,stable,b,c,d]));
    `);
    expect(hashes[0]).toMatch(/^[a-f0-9]{64}$/);
    expect(hashes[1]).toBe(hashes[0]);
    expect(new Set([hashes[0], ...hashes.slice(2)]).size).toBe(4);
  });

  test("fingerprints with Git from PATH when no managed Git is configured", () => {
    const hash = run(`console.log(JSON.stringify(await worktreeFingerprint(process.cwd())));`, { PI_TOOL_GIT: undefined });
    expect(hash).toMatch(/^[a-f0-9]{64}$/);
  });

  test("checks run through Bash with the requested cwd and inherited synthetic environment", () => {
    const result = run(`
      const result=await runPlan(executionPlan({command:'printf "%s|%s" "$PWD" "$PI_TEST_VALUE"',cwd:process.cwd()}));
      console.log(JSON.stringify(result));
    `, { PI_TEST_VALUE: "inherited-fixture" });
    expect(result.exitCode).toBe(0);
    expect(result.output).toBe(`${root}|inherited-fixture`);
  });

  test("actual process status and bounded timeout/abort/output capture", () => {
    const results = run(`
      const plan=code=>processPlan({executable:executable('node'),args:['-e',code],cwd:process.cwd()});
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
