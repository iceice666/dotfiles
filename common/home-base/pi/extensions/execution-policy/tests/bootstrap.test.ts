import { expect, test } from "bun:test";
import { mkdtempSync, copyFileSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

test("mandatory bootstrap exits on missing or broken enforcement before continuing", () => {
  const directory = mkdtempSync(join(tmpdir(), "pi-policy-bootstrap-"));
  try {
    const entry = join(directory, "bootstrap.ts");
    copyFileSync(join(import.meta.dir, "../bootstrap.ts"), entry);
    for (const implementation of [undefined, "this is invalid Typescript {", "export default () => { throw Error('failure'); }"]) {
      if (implementation !== undefined) writeFileSync(join(directory, "index.ts"), implementation);
      const result = spawnSync(process.execPath, ["-e", `const m=await import(${JSON.stringify(entry)}); await m.default({}); console.log('UNSAFE_CONTINUE');`], { encoding: "utf8", timeout: 10000 });
      expect(result.status).toBe(1);
      expect(result.stdout).not.toContain("UNSAFE_CONTINUE");
      expect(result.stderr).toContain("mandatory execution policy failed");
    }
  } finally { rmSync(directory, { recursive: true, force: true }); }
});
