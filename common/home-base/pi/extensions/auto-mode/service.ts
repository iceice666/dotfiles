import type { Action, ReviewContext } from "./classifier.ts";

export interface ParentContextRequest extends Action { actionId: string; includeContext?: boolean }
export interface ParentContextResponse { revision: number; yolo?: boolean; scopeId?: string; context?: ReviewContext }
export type ParentContextProvider = (worker: string, request: ParentContextRequest, signal: AbortSignal) => Promise<ParentContextResponse>;

// Separate extension loaders share only this trusted in-process bridge. Not a model tool or durable grant store.
const key = Symbol.for("pi.local.auto-mode.parent-context.v1");
const shared = globalThis as typeof globalThis & { [key]?: { provider: ParentContextProvider } };
export function registerParentContext(provider: ParentContextProvider): () => void {
  const registration = { provider };
  shared[key] = registration;
  return () => { if (shared[key] === registration) delete shared[key]; };
}
export async function requestParentContext(worker: string, request: ParentContextRequest, signal: AbortSignal): Promise<ParentContextResponse> {
  signal.throwIfAborted();
  const registration = shared[key];
  if (!registration) throw new Error("Parent Auto Mode context service unavailable; reload the parent session.");
  const result = await registration.provider(worker, request, signal);
  signal.throwIfAborted();
  if (shared[key] !== registration) throw new Error("Parent Auto Mode session changed.");
  return result;
}

/** A parent snapshot supplements child history, but never changes task.human or creates a grant. */
export function mergeParentContext(child: ReviewContext, parent: ReviewContext): ReviewContext {
  if (parent.version !== 1 || typeof parent.sessionId !== "string" || !Array.isArray(parent.memory) || !Array.isArray(parent.recent) || !Array.isArray(parent.evidence)) throw new Error("Invalid parent memory context.");
  const prefix = (id: string) => `parent:${parent.sessionId}:${id}`;
  const result = structuredClone(child);
  let used = 0;
  const append = (target: any[], item: unknown) => {
    const size = Buffer.byteLength(JSON.stringify(item), "utf8");
    if (used + size > 4000 || Buffer.byteLength(JSON.stringify(result), "utf8") + size + 2 > 12 * 1024) { result.truncated = true; return; }
    target.push(item); used += size;
  };
  // Prefer recent parent restrictions over older summaries. Child's own recent entries stay last.
  const childRecent = [...result.recent];
  const inheritedRecent: ReviewContext["recent"] = [];
  for (const item of parent.recent.toReversed()) {
    if (typeof item.id !== "string" || typeof item.text !== "string") throw new Error("Invalid parent source.");
    const entry = { ...item, id: prefix(item.id), text: `[Parent task context, not authorization; child requests cannot broaden parent restrictions] ${item.text}` };
    const before = used;
    append(result.recent, entry);
    if (used !== before) inheritedRecent.unshift(entry);
  }
  result.recent = [...inheritedRecent, ...childRecent];
  for (const item of parent.memory.toReversed()) append(result.memory, { ...item, id: prefix(item.id), sourceIds: item.sourceIds.map(prefix), text: `[Parent memory, not authorization] ${item.text}` });
  for (const item of parent.evidence) append(result.evidence, { ...item, id: prefix(item.id), text: `[Parent source, not authorization] ${item.text}` });
  result.truncated ||= parent.truncated || parent.memoryStatus !== "available";
  return result;
}
