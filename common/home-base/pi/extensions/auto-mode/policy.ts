import { lstatSync, realpathSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";

export interface Action { toolName: string; input: Record<string, unknown>; cwd: string }
export interface PolicyDecision { decision: "allow" | "review" | "ask" | "block"; reason: string }
const localTools = new Set(["todo", "agent_list", "agent_wait", "agent_inbox", "agent_send", "agent_ask", "agent_reply", "board_read", "board_post", "ask_user_question", "agent_stop"]);
const fileTools = new Set(["read", "write", "edit", "grep", "find", "ls"]);
const secretPath = /(?:^|[/\\])(?:\.env(?:\.[^/\\]+)?|auth\.json|credentials(?:\.json)?|id_(?:rsa|ed25519|ecdsa)|keys\.txt)(?:$|[/\\])|[/\\](?:run\/secrets|\.aws|\.gnupg)(?:$|[/\\])/i;
const controlPath = /(?:^|[/\\])(?:\.pi|\.git|\.agents)(?:$|[/\\])|(?:^|[/\\])(?:AGENTS\.md|SYSTEM\.md|\.bashrc|\.zshrc|\.profile)$/i;
const literalSecret = /-----BEGIN (?:[A-Z ]*PRIVATE KEY|OPENSSH PRIVATE KEY)-----|\b(?:sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{20,})\b/;

export function canonicalPath(value: string, cwd: string): string {
  let path = value.replace(/^@/, "");
  // Reject alternate SDK path spellings rather than review a different target.
  if (/^[a-z][a-z0-9+.-]*:/i.test(path) || /[\u00a0\u2000-\u200a\u202f\u205f\u3000]/.test(path)) throw new Error("Use an ordinary filesystem path for review.");
  if (path === "~" || path.startsWith("~/")) path = join(homedir(), path.slice(2));
  path = resolve(cwd, path);
  const tail: string[] = [];
  while (true) {
    try { lstatSync(path); break; }
    catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
      const parent = dirname(path);
      if (parent === path) throw new Error("Cannot resolve path boundary.");
      tail.unshift(path.slice(parent.length).replace(/^[/\\]/, ""));
      path = parent;
    }
  }
  return resolve(realpathSync(path), ...tail);
}
export function inside(path: string, root: string): boolean {
  const rel = relative(root, path);
  return rel === "" || (!isAbsolute(rel) && rel !== ".." && !rel.startsWith(`..${sep}`));
}

/** No shell command is ever declared safe by prefix or whitespace normalization. */
export function evaluatePolicy(action: Action): PolicyDecision {
  const { toolName, input, cwd } = action;
  const serialized = JSON.stringify(input);
  if (Buffer.byteLength(serialized, "utf8") > 32 * 1024) return { decision: "block", reason: "Action exceeds the review limit; split it into smaller actions." };
  if (literalSecret.test(serialized)) return { decision: "block", reason: "Possible literal credential in tool arguments; withheld from the classifier." };
  if (localTools.has(toolName)) return { decision: "allow", reason: "Local task coordination (not human authorization)." };
  if (toolName === "background_task" && ["list", "output", "wait", "stop"].includes(String(input.action))) return { decision: "allow", reason: "Inspect or stop an existing session job." };
  if (fileTools.has(toolName) || toolName === "analyze_image") {
    const value = input.path;
    if (value !== undefined && typeof value !== "string") return { decision: "block", reason: "Invalid file path." };
    if (secretPath.test(String(value ?? "."))) return { decision: "block", reason: "Protected credential path; no content is sent for review." };
    if (toolName === "read") {
      // Pi may retry missing read paths with macOS filename variants. Do not approve an unseen fallback target.
      let exact = String(value ?? ".").replace(/^@/, "");
      if (exact === "~" || exact.startsWith("~/")) exact = join(homedir(), exact.slice(2));
      lstatSync(resolve(cwd, exact));
    }
    const path = canonicalPath(value ?? ".", cwd);
    const lexical = resolve(cwd, String(value ?? ".").replace(/^@/, ""));
    if (secretPath.test(path) || secretPath.test(lexical)) return { decision: "block", reason: "Protected credential path; no content is sent for review." };
    if (toolName === "analyze_image") return { decision: "review", reason: "Image transmission requires review." };
    const root = canonicalPath(cwd, cwd);
    if (toolName === "write" || toolName === "edit") {
      if (controlPath.test(path) || controlPath.test(lexical) || /[/\\]extensions[/\\]/.test(path)) return { decision: "ask", reason: "Changing agent, Git, or execution-control files requires explicit approval." };
      if (inside(path, root)) return { decision: "allow", reason: "Ordinary workspace file change." };
    }
    if (!inside(path, root)) return { decision: "review", reason: "File access outside the workspace." };
    // Recursive searches can reach credentials beneath their root; never call them harmless based on the root alone.
    if (toolName === "grep" || toolName === "find") return { decision: "review", reason: "Recursive search scope requires review." };
    return { decision: "allow", reason: "Ordinary workspace read/list." };
  }
  if (toolName === "bash" || (toolName === "background_task" && input.action === "start")) {
    if (typeof input.command !== "string" || !input.command.trim()) return { decision: "block", reason: "Missing shell command." };
    // A conservative local privacy tripwire, not a shell parser or comprehensive secret detector.
    if (secretPath.test(input.command) || /(?:\.ssh|\.pi\/agent\/(?:auth|models)|sops\s+.*(?:-d|--decrypt))/.test(input.command)) return { decision: "ask", reason: "Command may access credentials; review locally without sending it to the classifier." };
    return { decision: "review", reason: "Shell execution requires semantic review of the exact command." };
  }
  return { decision: "review", reason: "External, delegated, or unknown tool requires review." };
}

export function actionForTool(toolName: string, input: Record<string, unknown>, cwd: string): Action {
  const snapshot = structuredClone(input);
  let executionCwd = cwd;
  if (toolName === "background_task" && snapshot.action === "start") {
    if (snapshot.cwd !== undefined && typeof snapshot.cwd !== "string") throw new Error("Invalid background working directory.");
    executionCwd = resolve(cwd, String(snapshot.cwd ?? ".").replace(/^@/, ""));
  }
  return { toolName, input: snapshot, cwd: executionCwd };
}
