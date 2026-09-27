import { existsSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import type { Action, ReviewContext } from "./classifier.ts";

// OM 3.1.3 internal reader contract. Only pure readers are loaded; never its extension entrypoint.
export interface Entry { id: string; type: string; parentId?: string | null; customType?: string; data?: any; message?: any; [key: string]: unknown }
interface Memory { id: string; content: string; sourceEntryIds?: string[]; supportingObservationIds?: string[]; timestamp?: string; relevance?: string }
export interface MemoryReader {
  fullProjection(entries: Entry[]): { observations: Memory[]; reflections: Memory[] };
  recallMemorySources(entries: Entry[], id: string): { sourceEntries: Entry[]; partial: boolean; collision: boolean; missingSourceEntryIds: string[] };
}
export interface Snapshot { sessionId: string; leafId: string | null; entries: Entry[] }
const MAX_CONTEXT_BYTES = 12 * 1024;
const bytes = (value: unknown) => Buffer.byteLength(JSON.stringify(value), "utf8");
let readerPromise: Promise<MemoryReader> | undefined;

export function loadMemoryReader(): Promise<MemoryReader> {
  return readerPromise ??= (async () => {
    const sibling = new URL("../observational-memory/session-ledger/", import.meta.url);
    let base = sibling;
    if (!existsSync(fileURLToPath(sibling))) {
      // Development dependency only; deployment supplies the pinned sibling from pi.nix.
      const require = createRequire(import.meta.url);
      const pkg = require.resolve("pi-observational-memory/package.json");
      const { version } = require(pkg);
      if (version !== "3.1.3") throw new Error("Unsupported memory reader version.");
      base = pathToFileURL(join(dirname(pkg), "src", "session-ledger") + "/");
    }
    const projection = await import(new URL("projection.ts", base).href);
    const recall = await import(new URL("recall.ts", base).href);
    if (typeof projection.fullProjection !== "function" || typeof recall.recallMemorySources !== "function") throw new Error("Memory reader unavailable.");
    return { fullProjection: projection.fullProjection, recallMemorySources: recall.recallMemorySources };
  })();
}

function textContent(content: unknown): string {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content.filter(part => part?.type === "text" && typeof part.text === "string").map(part => part.text).join("\n");
}
// Context is not a secret scanner. Avoid copying recognizable credential material into another request.
function safeText(text: string): string {
  return /-----BEGIN [A-Z ]*PRIVATE KEY-----|\b(?:sk-[\w-]{20,}|gh[pousr]_[\w]{20,})\b/.test(text)
    ? "[Credential-shaped context withheld]" : text;
}
function excerpt(text: string, maxBytes: number): { text: string; truncated: boolean } {
  text = safeText(text);
  if (Buffer.byteLength(text, "utf8") <= maxBytes) return { text, truncated: false };
  const chars = Array.from(text);
  const take = (list: string[], budget: number) => {
    let result = "";
    for (const char of list) { if (Buffer.byteLength(result + char, "utf8") > budget) break; result += char; }
    return result;
  };
  const head = take(chars, Math.floor((maxBytes - 100) / 2));
  const tail = Array.from(take(chars.toReversed(), Math.floor((maxBytes - 100) / 2))).reverse().join("");
  return { text: `${head}\n[Context excerpt; middle omitted, restrictions may be missing]\n${tail}`, truncated: true };
}

function source(entry: Entry): ReviewContext["evidence"][number] | undefined {
  if (entry.type !== "message" || !entry.message) return;
  const message = entry.message;
  if (message.role === "user") return { id: entry.id, role: "user", text: textContent(message.content) };
  if (message.role === "toolResult" && ["ask_user_question", "agent_ask"].includes(message.toolName)) {
    try {
      const raw = textContent(message.content);
      if (Buffer.byteLength(raw, "utf8") > 32000) return;
      const answer = JSON.parse(raw);
      if (!["answered", "cancelled", "unavailable"].includes(answer.status) || !Array.isArray(answer.answers)) return;
      // Historical answers are evidence only. No serialized claim of origin grants authority.
      const answers = answer.answers.slice(0, 4).map((item: any) => ({
        question: typeof item.question === "string" ? item.question : "",
        selected: Array.isArray(item.selected) ? item.selected.filter((s: unknown) => typeof s === "string") : [],
        ...(typeof item.customText === "string" ? { customText: item.customText } : {}),
      }));
      return { id: entry.id, role: "question-answer", toolName: message.toolName, text: JSON.stringify({ status: answer.status, answers }) };
    } catch { return; }
  }
  if (message.role === "assistant" && Array.isArray(message.content)) {
    const questions = message.content.filter((p: any) => p.type === "toolCall" && ["ask_user_question", "agent_ask"].includes(p.name))
      .map((p: any) => ({ toolName: p.name, arguments: p.arguments }));
    if (questions.length) return { id: entry.id, role: "assistant-question", text: JSON.stringify(questions) };
  }
}

/** Builds a bounded lower-trust envelope from a single current-branch snapshot. Never grants permission. */
export async function buildReviewContext(
  snapshot: Snapshot, action: Action, load: () => Promise<MemoryReader> = loadMemoryReader,
): Promise<ReviewContext> {
  const context: ReviewContext = { version: 1, sessionId: snapshot.sessionId, leafId: snapshot.leafId,
    memoryStatus: "unavailable", memory: [], recent: [], evidence: [], coverageId: null, truncated: false };
  const entries = snapshot.entries;
  const ids = new Set(entries.map(entry => entry.id));
  if (entries.length > 100000 || ids.size !== entries.length || (snapshot.leafId && !ids.has(snapshot.leafId))) {
    context.memoryStatus = "invalid"; context.truncated = true; return context;
  }
  const index = new Map(entries.map((entry, i) => [entry.id, i]));
  // Always reserve space for newest input and raw answers, even while OM lags or is absent.
  let recentBytes = 0;
  for (const entry of entries.toReversed()) {
    const item = source(entry);
    if (!item || item.role === "assistant-question" || !item.text) continue;
    const clipped = excerpt(item.text, 1500);
    const candidate = { ...item, role: item.role, text: clipped.text };
    if (context.recent.length >= 8 || recentBytes + bytes(candidate) > 5000) { context.truncated = true; continue; }
    context.recent.unshift(candidate);
    recentBytes += bytes(candidate);
    context.truncated ||= clipped.truncated;
  }
  let reader: MemoryReader;
  try { reader = await load(); } catch { return context; }
  try {
    const projection = reader.fullProjection(entries);
    if (!Array.isArray(projection.observations) || !Array.isArray(projection.reflections)) throw new Error();
    context.memoryStatus = "available";
    for (const entry of entries) {
      const marker = entry.data?.coversUpToId;
      if (entry.type === "custom" && entry.customType === "om.observations.recorded" && index.has(marker)
        && (index.get(marker)! > (index.get(context.coverageId ?? "") ?? -1))) context.coverageId = marker;
    }
    const terms = new Set(`${action.toolName} ${String(action.input.path ?? "")} ${String(action.input.command ?? "")}`.toLowerCase().match(/[a-z][a-z0-9_-]{2,}/g) ?? []);
    const candidates = [
      ...projection.observations.map(memory => ({ memory, kind: "observation" as const })),
      ...projection.reflections.map(memory => ({ memory, kind: "reflection" as const })),
    ].map((candidate, order) => {
      const text = candidate.memory.content.toLowerCase();
      const matches = [...terms].filter(term => text.includes(term)).length;
      return { ...candidate, order, score: matches * 5 + (candidate.memory.relevance === "critical" ? 4 : candidate.memory.relevance === "high" ? 2 : 0) };
    }).sort((a, b) => b.score - a.score || b.order - a.order);
    const recentIds = new Set(context.recent.map(item => item.id));
    let memoryBytes = 0, evidenceBytes = 0;
    for (const { memory, kind } of candidates) {
      if (context.memory.length >= 8) { context.truncated = true; break; }
      const recalled = reader.recallMemorySources(entries, memory.id);
      const sources = recalled.sourceEntries.filter(entry => ids.has(entry.id));
      const clipped = excerpt(memory.content, 1000);
      const item: ReviewContext["memory"][number] = { id: memory.id, kind, text: clipped.text,
        sourceIds: sources.map(entry => entry.id).slice(0, 16),
        sourceStatus: recalled.collision ? "ambiguous" : recalled.partial || !sources.length ? "partial" : "complete",
        ...(memory.timestamp ? { timestamp: memory.timestamp } : {}),
      };
      if (memoryBytes + bytes(item) > 4500) { context.truncated = true; continue; }
      context.memory.push(item); memoryBytes += bytes(item); context.truncated ||= clipped.truncated || sources.length > 16;
      for (const entry of sources) {
        if (recentIds.has(entry.id) || context.evidence.some(e => e.id === entry.id)) continue;
        const evidence = source(entry);
        if (!evidence || !evidence.text) continue;
        const text = excerpt(evidence.text, 900);
        const next = { ...evidence, text: text.text };
        if (evidenceBytes + bytes(next) > 2000) { context.truncated = true; continue; }
        context.evidence.push(next); evidenceBytes += bytes(next); context.truncated ||= text.truncated;
      }
    }
    // Source order is more reliable than a model-generated timestamp for interpreting corrections.
    context.memory.sort((a, b) => Math.max(-1, ...a.sourceIds.map(id => index.get(id) ?? -1)) - Math.max(-1, ...b.sourceIds.map(id => index.get(id) ?? -1)));
    context.evidence.sort((a, b) => index.get(a.id)! - index.get(b.id)!);
  } catch {
    context.memoryStatus = "invalid"; context.memory = []; context.evidence = []; context.coverageId = null;
  }
  if (bytes(context) > MAX_CONTEXT_BYTES) throw new Error("Review context exceeds budget.");
  return context;
}
