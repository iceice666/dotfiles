// Fixed local fingerprint program; Git hooks/fsmonitor and optional writes are disabled.
function fingerprintProgram() {
  const fs = require("node:fs");
  const path = require("node:path");
  const crypto = require("node:crypto");
  const { spawnSync } = require("node:child_process");
  const cwd = fs.realpathSync(process.cwd());
  const hash = crypto.createHash("sha256");
  let bytes = 0;
  let count = 0;
  const add = value => hash.update(JSON.stringify(value)).update("\n");
  const git = (args, allowEmpty = false) => {
    const result = spawnSync(process.env.PI_TOOL_GIT || "git", [
      "--no-pager", "--no-optional-locks", "-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null",
      "-c", "core.untrackedCache=false", "-c", "core.quotePath=false", ...args,
    ], {
      cwd, encoding: "utf8", timeout: 15000, maxBuffer: 16 * 1024 * 1024,
      env: {
        PATH: process.env.PATH, HOME: process.env.HOME, LC_ALL: "C",
        GIT_CONFIG_NOSYSTEM: "1", GIT_CONFIG_SYSTEM: "/dev/null", GIT_CONFIG_GLOBAL: "/dev/null",
        GIT_CONFIG_COUNT: "0", GIT_OPTIONAL_LOCKS: "0", GIT_TERMINAL_PROMPT: "0",
      },
    });
    if (result.error || result.signal || (result.status !== 0 && !(allowEmpty && result.status === 1 && !result.stdout && !result.stderr))) throw new Error("Git fingerprint failed: " + (result.error?.message || result.stderr));
    return result.stdout;
  };
  if (!fs.lstatSync(path.join(cwd, ".git")).isDirectory()) throw new Error("Verification requires a Git root with a local .git directory (no linked worktrees)");
  if (fs.realpathSync(git(["rev-parse", "--show-toplevel"]).trim()) !== cwd) throw new Error("Verification must run at the Git root");
  const stage = git(["ls-files", "--stage", "-z"]);
  if (stage.split("\0").some(row => row.startsWith("160000 "))) throw new Error("Submodules are not supported by verification fingerprints");
  add(["cwd", cwd]);
  add(["stage", stage]);
  const file = name => {
    if (++count > 100000) throw new Error("Fingerprint exceeds 100000 files");
    if (path.isAbsolute(name) || name.split("/").includes("..")) throw new Error("Invalid Git path");
    const parts = name.split("/");
    let current = cwd;
    for (const part of parts.slice(0, -1)) {
      current = path.join(current, part);
      let parent;
      try { parent = fs.lstatSync(current); }
      catch (error) {
        if (error.code !== "ENOENT") throw error;
        add([name, "missing"]);
        return;
      }
      if (!parent.isDirectory() || parent.isSymbolicLink()) throw new Error("Unsupported symlink ancestor");
    }
    const target = path.join(cwd, name);
    let stat;
    try { stat = fs.lstatSync(target); }
    catch (error) {
      if (error.code !== "ENOENT") throw error;
      add([name, "missing"]);
      return;
    }
    if (stat.isSymbolicLink()) { add([name, "symlink", fs.readlinkSync(target), stat.ino, stat.ctimeMs, stat.mtimeMs]); return; }
    if (!stat.isFile()) throw new Error("Unsupported non-file: " + name);
    bytes += stat.size;
    if (bytes > 256 * 1024 * 1024) throw new Error("Fingerprint exceeds 256 MiB");
    const fd = fs.openSync(target, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW);
    try {
      const after = fs.fstatSync(fd);
      if (!after.isFile() || after.size !== stat.size || after.ino !== stat.ino || after.mtimeMs !== stat.mtimeMs || after.ctimeMs !== stat.ctimeMs) throw new Error("File changed during fingerprint");
      const data = fs.readFileSync(fd);
      const final = fs.fstatSync(fd);
      if (data.length !== stat.size || final.mtimeMs !== stat.mtimeMs || final.ctimeMs !== stat.ctimeMs) throw new Error("File changed during fingerprint");
      add([name, stat.mode & 0o777, stat.ino, stat.mtimeMs, stat.ctimeMs, crypto.createHash("sha256").update(data).digest("hex")]);
    } finally { fs.closeSync(fd); }
  };
  // Include ref identities and config/index bytes, not just dirty-status labels.
  for (const name of [".git/HEAD", ".git/index", ".git/config", ".git/packed-refs", ".git/info/exclude"]) file(name);
  add(["refs", git(["show-ref", "--head", "--dereference"], true)]);
  const files = [...new Set(git(["ls-files", "-z", "--cached", "--others", "--exclude-standard"]).split("\0").filter(Boolean))].sort();
  for (const name of files) file(name);
  process.stdout.write(hash.digest("hex"));
}

export const FINGERPRINT_SCRIPT = `(${fingerprintProgram.toString()})()`;
