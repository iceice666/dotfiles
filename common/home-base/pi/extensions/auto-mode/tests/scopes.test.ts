import { afterEach, describe, expect, test } from "bun:test";
import { linkSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, unlinkSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import type { Action } from "../policy.ts";
import { ScopeStore } from "../scopes.ts";

const dirs: string[] = [];
afterEach(() => { for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true, force: true }); });
function fixture(worktree = false) {
  const base = mkdtempSync(join(tmpdir(), "pi-scopes-"));
  dirs.push(base);
  const repo = join(base, "repo");
  mkdirSync(repo);
  if (worktree) writeFileSync(join(repo, ".git"), "gitdir: /not-followed");
  else mkdirSync(join(repo, ".git"));
  mkdirSync(join(repo, "src"));
  writeFileSync(join(repo, "src", "main.ts"), "original");
  return { base, repo, store: new ScopeStore({ cwd: repo }) };
}
function action(cwd: string, path: string, toolName = "read"): Action {
  return { cwd, toolName, input: { path, content: "replacement", edits: [] } };
}

describe("session file scopes", () => {
  test("previews existing paths without granting; add/list return defensive copies", () => {
    const { repo, store } = fixture();
    expect(store.preview("src")).toMatchObject({ kind: "directory" });
    expect(store.list()).toEqual([]);
    expect(store.revision).toBe(0);
    const grant = store.add("src");
    expect(store.revision).toBe(1);
    expect(store.match(action(repo, "src/main.ts"))).toEqual(grant);
    grant.path = "/";
    const listed = store.list();
    listed[0].path = "/";
    expect(store.match(action(repo, "src/main.ts"))?.path).not.toBe("/");
    expect(readFileSync(join(repo, "src/main.ts"), "utf8")).toBe("original");
  });

  test("only read/write/edit are scoped, including new writes but not missing reads/edits", () => {
    const { repo, store } = fixture();
    store.add("src");
    for (const tool of ["read", "write", "edit"]) expect(store.match(action(repo, "src/main.ts", tool))).toBeDefined();
    for (const tool of ["bash", "background_task", "grep", "find", "ls", "analyze_image", "agent_send", "deploy"]) {
      expect(store.match(action(repo, "src/main.ts", tool))).toBeUndefined();
    }
    expect(store.match(action(repo, "src/new/sub/file.ts", "write"))).toBeDefined();
    expect(store.match(action(repo, "src/missing", "read"))).toBeUndefined();
    expect(store.match(action(repo, "src/missing", "edit"))).toBeUndefined();
    expect(store.match(action(repo, "src", "read"))).toBeUndefined();
    expect(store.match({ cwd: repo, toolName: "read", input: {} })).toBeUndefined();
    expect(store.match(null as unknown as Action)).toBeUndefined();
  });

  test("file scope never covers siblings, prefix lookalikes, or children", () => {
    const { repo, store } = fixture();
    const grant = store.add("src/main.ts");
    expect(store.match(action(repo, "src/main.ts"))).toEqual(grant);
    expect(store.match(action(repo, "src/main.ts.bak", "write"))).toBeUndefined();
    expect(store.match(action(repo, "src/other.ts", "write"))).toBeUndefined();
    expect(store.match(action(repo, "src/main.ts/child", "write"))).toBeUndefined();
    unlinkSync(join(repo, "src/main.ts"));
    expect(store.match(action(repo, "src/main.ts", "write"))).toBeUndefined();
  });

  test("repository roots are discovered from subdirectories and worktree markers", () => {
    const { repo } = fixture(true);
    const store = new ScopeStore({ cwd: join(repo, "src") });
    store.add(".");
    expect(store.match(action(join(repo, "src"), "main.ts"))).toBeDefined();
    expect(() => store.add("../src/missing")).toThrow();
    const noRepo = mkdtempSync(join(tmpdir(), "pi-no-repo-"));
    dirs.push(noRepo);
    expect(() => new ScopeStore({ cwd: noRepo })).toThrow("Git repository");
  });

  test("rejects repository and grant escapes, prefix collisions, and outside working directories", () => {
    const { repo, base, store } = fixture();
    mkdirSync(join(repo, "src-other"));
    writeFileSync(join(repo, "src-other", "main.ts"), "x");
    mkdirSync(join(base, "repo-other"));
    writeFileSync(join(base, "repo-other", "main.ts"), "x");
    store.add("src");
    expect(store.match(action(repo, "src-other/main.ts"))).toBeUndefined();
    expect(store.match(action(repo, "src/../../repo-other/main.ts"))).toBeUndefined();
    expect(store.match(action(base, join(repo, "src/main.ts")))).toBeUndefined();
    expect(() => store.preview("../repo-other")).toThrow("outside");
    expect(() => store.add("../repo-other")).toThrow("outside");
  });

  test("explicit repository scope still excludes controls and credentials for every file tool", () => {
    const { repo, store } = fixture();
    store.add(".");
    const protectedPaths = [
      ".git/config", ".pi/settings.json", ".agents/task.txt", "AGENTS.md", "src/SYSTEM.md", ".ssh/config", ".aws/config", ".gnupg/pubring",
      ".bashrc", ".zshrc", ".profile", ".env", ".env.local", ".envrc", "src/auth.json", "src/credentials", "src/credentials.json", "src/id_ed25519", "src/keys.txt",
      "src/private-key.pem", "src/secret.key", "src/cert.p12",
    ];
    for (const path of protectedPaths) {
      const parts = path.split("/");
      mkdirSync(join(repo, ...parts.slice(0, -1)), { recursive: true });
      writeFileSync(join(repo, path), "sensitive");
      expect(() => store.preview(path)).toThrow();
      for (const tool of ["read", "write", "edit"]) expect(store.match(action(repo, path, tool))).toBeUndefined();
    }
    expect(store.match(action(repo, "src/main.ts"))).toBeDefined();
  });

  test("repository extension source is eligible but supplied live runtime roots are not", () => {
    const { repo } = fixture();
    const source = "common/home-base/pi/extensions/example";
    const live = "runtime-loaded";
    for (const path of [source, live]) { mkdirSync(join(repo, path), { recursive: true }); writeFileSync(join(repo, path, "index.ts"), "x"); }
    const store = new ScopeStore({ cwd: repo, protectedRoots: [join(repo, live)] });
    store.add(".");
    expect(store.match(action(repo, `${source}/index.ts`, "write"))).toBeDefined();
    for (const tool of ["read", "write", "edit"]) expect(store.match(action(repo, `${live}/index.ts`, tool))).toBeUndefined();
    expect(() => store.add(live)).toThrow("live control");
    for (const path of ["/nix/store", join(homedir(), ".pi"), join(homedir(), ".agents"), join(homedir(), ".config")]) {
      expect(() => store.add(path)).toThrow();
      expect(store.match(action(repo, path, "write"))).toBeUndefined();
    }
  });

  test("symlink targets must remain lexically and canonically within grant and repository", () => {
    const { base, repo, store } = fixture();
    writeFileSync(join(base, "outside"), "x");
    writeFileSync(join(repo, "sibling"), "x");
    symlinkSync(join(base, "outside"), join(repo, "src/outside"));
    symlinkSync(join(repo, "sibling"), join(repo, "src/sibling"));
    symlinkSync(join(repo, "src/main.ts"), join(repo, "alias"));
    symlinkSync(join(repo, "missing"), join(repo, "src/dangling"));
    store.add("src");
    for (const path of ["src/outside", "src/sibling", "alias", "src/dangling"]) {
      expect(store.match(action(repo, path))).toBeUndefined();
      expect(store.match(action(repo, path, "write"))).toBeUndefined();
    }
    expect(() => store.add("src/dangling")).toThrow();
    expect(() => store.add("src/outside")).toThrow();
  });

  test("retargeted approved symlinks invalidate the approval rather than following the new root", () => {
    const { repo, store } = fixture();
    mkdirSync(join(repo, "other"));
    writeFileSync(join(repo, "other/main.ts"), "x");
    symlinkSync(join(repo, "src"), join(repo, "linked"));
    store.add("linked");
    expect(store.match(action(repo, "linked/main.ts"))).toBeDefined();
    unlinkSync(join(repo, "linked"));
    symlinkSync(join(repo, "other"), join(repo, "linked"));
    expect(store.match(action(repo, "linked/main.ts"))).toBeUndefined();
    expect(store.match(action(repo, "other/main.ts"))).toBeUndefined();
  });

  test("hardlinks are rejected at preview and rechecked after approval", () => {
    const { base, repo, store } = fixture();
    store.add("src");
    linkSync(join(repo, "src/main.ts"), join(base, "hardlink"));
    expect(() => store.add("src/main.ts")).toThrow("non-hardlinked");
    for (const tool of ["read", "write", "edit"]) expect(store.match(action(repo, "src/main.ts", tool))).toBeUndefined();
  });

  test("revocation, clear, and fresh instances never retain old approvals", () => {
    const { repo, store } = fixture();
    const grant = store.add("src");
    store.revoke(grant.id);
    expect(store.revision).toBe(2);
    expect(store.match(action(repo, "src/main.ts"))).toBeUndefined();
    store.add("src");
    store.revoke("all");
    expect(store.list()).toEqual([]);
    store.add("src");
    expect(new ScopeStore({ cwd: repo }).match(action(repo, "src/main.ts"))).toBeUndefined();
    store.clear();
    expect(store.revision).toBe(6);
    expect(store.list()).toEqual([]);
  });

  test("parent traversal through symlinks is never normalized into a different approved action", () => {
    const { base, repo, store } = fixture();
    mkdirSync(join(base, "outside"));
    writeFileSync(join(repo, "src/file.ts"), "safe");
    writeFileSync(join(base, "file.ts"), "outside");
    symlinkSync(join(base, "outside"), join(repo, "src/link"));
    store.add("src");
    expect(store.match(action(repo, "src/link/../file.ts"))).toBeUndefined();
    expect(store.match(action(repo, "src/link/../file.ts", "write"))).toBeUndefined();
    expect(() => store.add("src/link/../file.ts")).toThrow("parent traversal");
  });

  test("runtime roots remain protected through aliases and changed symlink targets", () => {
    const { repo } = fixture();
    mkdirSync(join(repo, "runtime"));
    writeFileSync(join(repo, "runtime/live.ts"), "x");
    mkdirSync(join(repo, "runtime-next"));
    writeFileSync(join(repo, "runtime-next/live.ts"), "x");
    symlinkSync(join(repo, "runtime"), join(repo, "loaded"));
    symlinkSync(join(repo, "runtime"), join(repo, "src/alias"));
    const store = new ScopeStore({ cwd: repo, protectedRoots: [join(repo, "loaded")] });
    store.add(".");
    expect(store.match(action(repo, "src/alias/live.ts"))).toBeUndefined();
    unlinkSync(join(repo, "loaded"));
    symlinkSync(join(repo, "runtime-next"), join(repo, "loaded"));
    for (const path of ["runtime/live.ts", "runtime-next/live.ts", "loaded/live.ts"]) {
      expect(store.match(action(repo, path))).toBeUndefined();
    }
  });

  test("retargeted repository working-directory links invalidate existing grants", () => {
    const { repo, base } = fixture();
    const other = join(base, "other-repo");
    mkdirSync(join(other, ".git"), { recursive: true });
    mkdirSync(join(other, "src"));
    writeFileSync(join(other, "src/main.ts"), "x");
    const alias = join(base, "repo-link");
    symlinkSync(repo, alias);
    const store = new ScopeStore({ cwd: alias });
    store.add("src");
    expect(store.match(action(alias, "src/main.ts"))).toBeDefined();
    unlinkSync(alias);
    symlinkSync(other, alias);
    expect(store.match(action(alias, "src/main.ts"))).toBeUndefined();
  });

  test("removing the Git marker invalidates all matches", () => {
    const { repo, store } = fixture();
    store.add("src");
    rmSync(join(repo, ".git"), { recursive: true });
    expect(store.match(action(repo, "src/main.ts"))).toBeUndefined();
  });
});
