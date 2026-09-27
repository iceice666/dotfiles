import { dirname, join } from "node:path";
import { inside } from "./policy.ts";

export interface ToolSource { name: string; sourceInfo?: { path?: string } }
export interface BoundaryStatus { ok: boolean; reason?: string }
export interface Attestation { confined: boolean; reason: string }

// The managed launcher loads every extension with `-e` from one content-addressed tree.
const MANAGED_TREE = /^\/nix\/store\/[0-9a-z]{32}-pi-extensions$/;

/** The immutable extension tree containing this module, or undefined for mutable/unmanaged copies. */
export function managedRoot(modulePath: string): string | undefined {
  const root = dirname(dirname(modulePath));
  return MANAGED_TREE.test(root) ? root : undefined;
}

const within = (path: string | undefined, root: string) => !!path && path !== root && inside(path, root);

/**
 * Auto Mode reviews intent on the assumption that file/shell tools are OS-confined. Verify that
 * assumption instead of trusting it: auto-discovered copies, mixed extension versions after a
 * switch, and a missing launcher toolchain all make the review boundary meaningless.
 */
export function attestRuntime(options: { root: string | undefined; tools: ToolSource[]; toolName: string; boundary: BoundaryStatus }): Attestation {
  const { root, tools, toolName, boundary } = options;
  if (!root) return { confined: false, reason: "Auto Mode was not loaded from the managed immutable extension tree (unmanaged Pi, SDK embedding, or a mutable auto-discovered copy)." };
  if (!boundary.ok) return { confined: false, reason: boundary.reason || "Restricted execution is unavailable." };
  const source = (name: string) => tools.find(tool => tool.name === name)?.sourceInfo?.path;
  for (const name of ["read", "bash"]) {
    if (!within(source(name), join(root, "execution-policy"))) return { confined: false, reason: `The ${name} tool is not provided by the managed execution policy.` };
  }
  if (!within(source(toolName), root)) return { confined: false, reason: `The ${toolName} tool is not provided by the managed extension tree.` };
  return { confined: true, reason: "" };
}
