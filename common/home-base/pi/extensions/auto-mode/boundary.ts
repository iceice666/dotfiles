import { dirname } from "node:path";
import { inside } from "./policy.ts";

export interface ToolSource { name: string; sourceInfo?: { path?: string; source?: string } }
export interface Attestation { managed: boolean; reason: string }

// The managed launcher loads every extension with `-e` from one content-addressed tree.
const MANAGED_TREE = /^\/nix\/store\/[0-9a-z]{32}-pi-extensions$/;
const BUILTIN_TOOLS = new Set(["read", "bash", "powershell", "write", "edit", "grep", "find", "ls"]);

/** The immutable extension tree containing this module, or undefined for mutable/unmanaged copies. */
export function managedRoot(modulePath: string): string | undefined {
  const root = dirname(dirname(modulePath));
  return MANAGED_TREE.test(root) ? root : undefined;
}

const within = (path: string | undefined, root: string) => !!path && path !== root && inside(path, root);

/** Verify tool provenance, not confinement: built-ins and trusted extensions run with host permissions. */
export function attestRuntime(options: { root: string | undefined; tools: ToolSource[]; toolName: string }): Attestation {
  const { root, tools, toolName } = options;
  if (!root || !MANAGED_TREE.test(root)) return { managed: false, reason: "Auto Mode was not loaded from the managed immutable extension tree (unmanaged Pi, SDK embedding, or a mutable auto-discovered copy)." };
  const source = tools.find(tool => tool.name === toolName)?.sourceInfo;
  const builtin = source?.source === "builtin" && BUILTIN_TOOLS.has(toolName) && source.path === `<builtin:${toolName}>`;
  const extension = !!source?.source && source.source !== "builtin" && source.source !== "sdk" && within(source.path, root);
  if (!builtin && !extension) return { managed: false, reason: `The ${toolName} tool is neither an upstream built-in nor provided by the managed extension tree.` };
  return { managed: true, reason: "" };
}
