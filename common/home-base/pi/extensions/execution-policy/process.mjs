import { accessSync, constants, lstatSync, mkdirSync, mkdtempSync, opendirSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { basename, dirname, isAbsolute, join, relative } from "node:path";

// Only trusted startup state configures the boundary. Later env/cwd changes cannot
// expand it. The managed launcher supplies immutable toolchain paths.
const START_ENV = Object.freeze({ ...process.env });
const START_WORKSPACE = realpathSync(START_ENV.PI_EXECUTION_WORKSPACE || process.cwd());
const START_TMP = realpathSync(tmpdir());
const START_HOME = realpathSync(homedir());
const CONTROL = /^(?:\.git|\.pi|\.agents|\.claude|\.cursor|AGENTS(?:\.override)?\.md|CLAUDE\.md|SYSTEM\.md|APPEND_SYSTEM\.md)$/;
const SECRET = /^(?:\.env.*|\.ssh|\.aws|\.gnupg|\.kube|\.netrc|\.npmrc|\.pypirc|keys\.txt|id_[^/]*|auth(?:\.json)?|credentials(?:\.[^/]*)?)$/;
const CONTROL_PATTERN = "(\\.git|\\.pi|\\.agents|\\.claude|\\.cursor|AGENTS(\\.override)?\\.md|CLAUDE\\.md|SYSTEM\\.md|APPEND_SYSTEM\\.md)";
const SECRET_PATTERN = "(\\.env[^/]*|\\.ssh|\\.aws|\\.gnupg|\\.kube|\\.netrc|\\.npmrc|\\.pypirc|keys\\.txt|id_[^/]*|auth(\\.json)?|credentials(\\.[^/]*)?)";

function inside(root, path) {
  const rel = relative(root, path);
  return rel === "" || (!rel.startsWith("../") && rel !== ".." && !isAbsolute(rel));
}

export function executionWorkspace() { return START_WORKSPACE; }

const UNMANAGED = "Restricted execution unavailable: the pinned /nix/store toolchain is missing or invalid, so this Pi process was probably not started by the managed `pi` launcher; no host fallback. This is a security boundary, not a transient fault: do not run the operation through other tools, background jobs or workers. Ask the human to exit and restart Pi with the managed launcher (check `type -a pi`).";

function immutablePath(path) {
  if (!path || !isAbsolute(path) || !path.startsWith("/nix/store/")) throw new Error(UNMANAGED);
  const resolved = realpathSync(path);
  if (!resolved.startsWith("/nix/store/")) throw new Error("Toolchain symlink escapes /nix/store.");
  return resolved;
}

export function trustedExecutable(name) {
  if (!["bash", "node", "git", "bwrap", "env"].includes(name)) throw new Error("Unknown trusted executable.");
  const result = immutablePath(START_ENV[`PI_SANDBOX_${name.toUpperCase()}`]);
  if (!lstatSync(result).isFile()) throw new Error("Trusted executable must be a regular file.");
  accessSync(result, constants.X_OK);
  return result;
}

function trustedPath() {
  const entries = START_ENV.PI_SANDBOX_PATH?.split(":");
  if (!entries?.length || entries.some(path => !path)) throw new Error(UNMANAGED);
  return entries.map(immutablePath).join(":");
}

/** Non-throwing readiness probe for status and Auto Mode attestation. Operations still revalidate. */
export function boundaryStatus() {
  try {
    if (!["darwin", "linux"].includes(process.platform)) throw new Error("Restricted execution is unsupported on this platform; no fallback.");
    for (const name of ["bash", "node", "git", ...(process.platform === "linux" ? ["env", "bwrap"] : [])]) trustedExecutable(name);
    trustedPath();
    if (process.platform === "darwin") accessSync("/usr/bin/sandbox-exec", constants.X_OK);
    return { ok: true };
  } catch (error) {
    return { ok: false, reason: error instanceof Error ? error.message : String(error) };
  }
}

// This preflight rejects inode aliases to host files and special devices/FIFOs.
// It is bounded and never follows symlinks. Concurrent malicious *host* changes
// are outside the threat model; sandbox children remain kernel-confined.
function inspectWorkspace(workspace) {
  const protectedPaths = [];
  const secrets = [];
  let count = 0;
  const started = Date.now();
  const pending = [{ path: workspace, depth: 0 }];
  while (pending.length) {
    const { path, depth } = pending.pop();
    if (++count > 200000 || depth > 128 || Date.now() - started > 10000) throw new Error("Workspace safety scan exceeded its bound; choose a smaller workspace.");
    const stat = lstatSync(path);
    const name = basename(path);
    const secret = path !== workspace && SECRET.test(name);
    const control = path !== workspace && CONTROL.test(name);
    if ((secret || control) && stat.isSymbolicLink()) throw new Error(`Protected paths cannot be symlinks: ${path}`);
    if (stat.isFile() && stat.nlink > 1) throw new Error(`Hardlinked workspace file refused: ${path}`);
    if (!stat.isFile() && !stat.isDirectory() && !stat.isSymbolicLink()) throw new Error(`Special workspace file refused: ${path}`);
    if (secret) secrets.push({ path, directory: stat.isDirectory() });
    if (control) protectedPaths.push(path);
    if (stat.isDirectory()) {
      const dir = opendirSync(path);
      try {
        let entry;
        while ((entry = dir.readSync())) {
          if (pending.length + count > 200000) throw new Error("Workspace safety scan exceeded its bound; choose a smaller workspace.");
          pending.push({ path: join(path, entry.name), depth: depth + 1 });
        }
      } finally { dir.closeSync(); }
    }
  }
  // Parent masks supersede descendants, avoiding invalid nested mount targets.
  const secretNames = new Set(secrets.map(item => item.path));
  const controlNames = new Set(protectedPaths);
  const hasAncestor = (path, names, includeSelf = false) => {
    for (let parent = includeSelf ? path : dirname(path); inside(workspace, parent); parent = dirname(parent)) {
      if (names.has(parent)) return true;
      if (parent === workspace) break;
    }
    return false;
  };
  return {
    secrets: secrets.filter(item => !hasAncestor(item.path, secretNames)),
    protectedPaths: protectedPaths.filter(path => !hasAncestor(path, secretNames, true) && !hasAncestor(path, controlNames)),
  };
}

const quote = value => JSON.stringify(value);
const regexEscape = value => value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

function darwinProfile(workspace, scratch, readOnly) {
  const workspaceRegex = `^${regexEscape(workspace)}/([^/]+/)*`;
  // realpath/lstat and Git traverse ancestors; metadata is not directory content.
  const ancestors = new Set(["/nix", "/usr", "/System", "/var", "/tmp"]);
  for (const path of [workspace, scratch]) {
    for (let parent = dirname(path); parent !== "/"; parent = dirname(parent)) ancestors.add(parent);
  }
  return `(version 1)
(deny default)
(allow process-exec process-fork)
(allow signal (target self))
(allow sysctl-read (sysctl-name-regex #"^hw[.]")
  (sysctl-name "kern.osrelease") (sysctl-name "kern.ostype") (sysctl-name "kern.osversion")
  (sysctl-name "kern.version") (sysctl-name "kern.argmax"))
(allow file-read* (subpath "/nix/store") (subpath "/usr/lib") (subpath "/usr/bin") (subpath "/usr/share")
  (subpath "/bin") (subpath "/System/Library")
  (literal "/") (literal "/dev") (literal "/private") (literal "/private/var")
  (literal "/dev/null") (literal "/dev/zero") (literal "/dev/random") (literal "/dev/urandom")
  (literal "/private/etc/localtime"))
(allow file-read-metadata ${[...ancestors].map(path => `(literal ${quote(path)})`).join(" ")})
(allow file-read* (subpath ${quote(workspace)}) (subpath ${quote(scratch)}))
(allow file-write* (subpath ${quote(scratch)}) ${readOnly ? "" : `(subpath ${quote(workspace)})`}
  (literal "/dev/null"))
(deny file-write* (regex ${quote(`${workspaceRegex}${CONTROL_PATTERN}(/|$)`)}))
(deny file-read* file-write* (regex ${quote(`${workspaceRegex}${SECRET_PATTERN}(/|$)`)}))
(deny file-link)
(deny network*)
`;
}

/** Pure argv builder for Linux contract tests; sandboxPlan validates all inputs. */
export function linuxSandboxArguments({ executable, args, cwd, workspace, scratch, env, bash, envExecutable, readOnly, secrets = [], protectedPaths = [] }) {
  const result = ["--die-with-parent", "--new-session", "--unshare-all", "--cap-drop", "ALL", "--clearenv",
    "--ro-bind", "/nix/store", "/nix/store", "--proc", "/proc", "--dev", "/dev", "--tmpfs", "/tmp", "--dir", "/tmp/home",
    readOnly ? "--ro-bind" : "--bind", workspace, workspace];
  if (bash) result.push("--symlink", bash, "/bin/sh");
  if (envExecutable) result.push("--symlink", envExecutable, "/usr/bin/env");
  for (const path of protectedPaths) result.push("--ro-bind", path, path);
  for (const secret of secrets) {
    if (secret.directory) result.push("--tmpfs", secret.path, "--remount-ro", secret.path);
    else result.push("--ro-bind", join(scratch, "empty"), secret.path);
  }
  for (const [key, value] of Object.entries(env)) result.push("--setenv", key, value);
  result.push("--chdir", cwd, "--", executable, ...args);
  return result;
}

export function sandboxPlan({ executable, args = [], cwd, workspace = START_WORKSPACE, readOnly = false }) {
  if (!["darwin", "linux"].includes(process.platform)) throw new Error("Restricted execution is unsupported on this platform; no fallback.");
  workspace = realpathSync(workspace);
  cwd = realpathSync(cwd || workspace);
  if (workspace === "/" || !inside(START_WORKSPACE, workspace) || !inside(workspace, cwd)) throw new Error("Requested cwd/workspace escapes the original execution workspace.");
  if (inside(workspace, START_HOME) || inside(workspace, START_TMP)) throw new Error("Refusing a broad home/temp workspace; select a project subdirectory.");
  if (workspace.split("/").some(part => CONTROL.test(part) || SECRET.test(part))) throw new Error("Sandbox workspace cannot be inside a protected or credential path.");
  if (!lstatSync(workspace).isDirectory() || !lstatSync(cwd).isDirectory()) throw new Error("Sandbox workspace/cwd must be directories.");
  executable = immutablePath(executable);
  accessSync(executable, constants.X_OK);
  if (!Array.isArray(args) || args.some(arg => typeof arg !== "string" || arg.includes("\0"))) throw new Error("Invalid sandbox arguments.");
  const path = trustedPath();
  const git = trustedExecutable("git");
  const scanned = inspectWorkspace(workspace);
  const backend = process.platform === "darwin" ? "/usr/bin/sandbox-exec" : trustedExecutable("bwrap");
  accessSync(backend, constants.X_OK);
  const scratch = realpathSync(mkdtempSync(join(START_TMP, "pi-sandbox-")));
  const cleanup = () => rmSync(scratch, { recursive: true, force: true });
  try {
    mkdirSync(join(scratch, "home"), { mode: 0o700 });
    writeFileSync(join(scratch, "empty"), "", { mode: 0o400 });
    const temp = process.platform === "darwin" ? scratch : "/tmp";
    const env = {
      PATH: path, HOME: join(temp, "home"), TMPDIR: temp, TMP: temp, TEMP: temp,
      LANG: "en_US.UTF-8", LC_ALL: "en_US.UTF-8", TERM: "dumb", PWD: cwd,
      PI_EXECUTION_WORKSPACE: workspace, PI_SANDBOX_GIT: git,
      GIT_CONFIG_NOSYSTEM: "1", GIT_CONFIG_GLOBAL: "/dev/null", GIT_TERMINAL_PROMPT: "0",
    };
    const planArgs = process.platform === "darwin"
      ? ["-p", darwinProfile(workspace, scratch, readOnly), executable, ...args]
      : linuxSandboxArguments({ executable, args, cwd, workspace, scratch, env, readOnly, bash: trustedExecutable("bash"), envExecutable: trustedExecutable("env"), ...scanned });
    return { command: backend, args: planArgs, options: { cwd, env }, cleanup };
  } catch (error) { cleanup(); throw error; }
}

export function executionPlan({ command, cwd, workspace, readOnly = false }) {
  if (typeof command !== "string" || command.includes("\0")) throw new Error("Invalid shell command.");
  return sandboxPlan({ executable: trustedExecutable("bash"), args: ["--noprofile", "--norc", "-c", command], cwd, workspace, readOnly });
}
