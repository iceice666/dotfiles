import { realpathSync } from "node:fs";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { createReadToolDefinition, createWriteToolDefinition, createEditToolDefinition, createBashToolDefinition, createLsToolDefinition } from "@earendil-works/pi-coding-agent";
import { fileOperation, sandboxRead, shellOperations } from "./io.ts";
import { executionWorkspace } from "./process.mjs";

// Only these repo-owned capabilities have an audited execution path. Unknown tools
// cannot become unrestricted merely because an intent classifier approves them.
const ALLOWED = new Set([
  "read", "write", "edit", "bash", "ls", "background_task", "todo",
  "agent_spawn", "agent_list", "agent_wait", "agent_send", "agent_ask", "agent_reply",
  "agent_inbox", "agent_stop", "board_post", "board_read", "ask_user_question",
  "web_search", "analyze_image", "recall",
]);

export function executionDecision(name: string): { block: true; reason: string } | undefined {
  if (!ALLOWED.has(name)) return {
    block: true,
    reason: `Restricted execution: ${name} has no audited sandbox adapter. Use a supported capability or ask the human to run the action outside Pi. Approval does not expand the OS sandbox.`,
  };
}

export default function executionPolicy(pi: ExtensionAPI) {
  // The managed launcher supplies the original scope to every worker. A resumed
  // session or alternate cwd cannot silently widen it.
  const workspace = executionWorkspace();
  const shell = shellOperations(workspace);
  const cwd = () => process.cwd();
  const io = (op: string, path: string, content?: string) => fileOperation(op, path, cwd(), workspace, undefined, content);
  const read = (path: string) => sandboxRead(path, cwd(), workspace);
  const readDefinition = createReadToolDefinition(cwd(), {
    operations: { readFile: read, access: async path => { await io("access", path); }, detectImageMimeType: async path => {
      const bytes = await read(path);
      if (bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) return "image/png";
      if (bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255) return "image/jpeg";
      if (["GIF87a", "GIF89a"].includes(bytes.toString("ascii", 0, 6))) return "image/gif";
      if (bytes.toString("ascii", 0, 4) === "RIFF" && bytes.toString("ascii", 8, 12) === "WEBP") return "image/webp";
      return null;
    } },
  });
  pi.registerTool(readDefinition);
  pi.registerTool(createWriteToolDefinition(cwd(), { operations: {
    writeFile: async (path, content) => { await io("write", path, content); },
    mkdir: async path => { await io("mkdir", path); },
  } }));
  pi.registerTool(createEditToolDefinition(cwd(), { operations: {
    readFile: read,
    writeFile: async (path, content) => { await io("write", path, content); },
    access: async path => { await io("access", path); },
  } }));
  pi.registerTool(createLsToolDefinition(cwd(), { operations: {
    exists: path => io("exists", path),
    stat: async path => { const result = await io("stat", path); return { isDirectory: () => result.directory }; },
    readdir: path => io("readdir", path),
  } }));
  pi.registerTool(createBashToolDefinition(cwd(), { operations: shell, exposeSessionEnvironment: false }));
  pi.on("tool_call", event => executionDecision(event.toolName));
  pi.on("user_bash", () => ({ operations: shell }));
  pi.on("session_start", (_event, ctx) => {
    const selected = process.env.PI_EXECUTION_TOOLS?.split(",");
    pi.setActiveTools(pi.getActiveTools().filter(name => ALLOWED.has(name) && (!selected || selected.includes(name))));
    try {
      const current = realpathSync(ctx.cwd);
      if (current !== workspace && !current.startsWith(`${workspace}/`)) throw new Error("Outside workspace");
    } catch {
      // Tools still enforce their captured boundary independently.
      if (ctx.hasUI) ctx.ui.notify("Session cwd is missing or outside the original sandbox workspace; start a new Pi process in the intended workspace.", "warning");
    }
    if (ctx.hasUI) ctx.ui.setStatus("execution-policy", "sandbox:workspace / offline");
  });
  pi.on("before_agent_start", event => ({ systemPrompt: `${event.systemPrompt}\n\nRestricted execution is mandatory: file and shell tools execute inside the OS sandbox. Writes are limited to the original workspace and private scratch; shell has no network or host credentials. Background jobs, verification and workers inherit this boundary. Auto Mode approvals never lift it. Unknown/unadapted tools are unavailable. Use sandboxed bash with rg/find for recursive search. Nix daemon builds, downloads, SSH/deploy and browser CLI may require a human's external terminal. Do not retry a blocked action through a different capability. Trusted model and public-search requests remain on the host.` }));
  pi.registerCommand("sandbox", {
    description: "Show the immutable restricted execution boundary (no disable or escalation command)",
    handler: async (_args, ctx) => ctx.ui.notify(`Workspace: ${workspace}\nBackend: ${process.platform === "darwin" ? "Seatbelt" : process.platform === "linux" ? "bubblewrap" : "unsupported (fail closed)"}\nNo shell network, no host credentials, no approval-based sandbox escalation. Trusted extensions run on the host.`, "info"),
  });
}
