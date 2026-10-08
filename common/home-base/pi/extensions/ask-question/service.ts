import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Type, type Static } from "typebox";
import { showQuestionnaire } from "./ui.ts";

export const QuestionFields = {
  question: Type.String({ minLength: 1, maxLength: 12000, description: "Question for the human user" }),
  header: Type.Optional(Type.String({ maxLength: 120 })),
  options: Type.Optional(Type.Array(Type.Object({
    label: Type.String({ minLength: 1, maxLength: 1000 }),
    description: Type.Optional(Type.String({ maxLength: 4000 })),
  }), { maxItems: 12 })),
  multiSelect: Type.Optional(Type.Boolean()),
};
export const QuestionSchema = Type.Object(QuestionFields);
export const QuestionsSchema = Type.Object({ questions: Type.Array(QuestionSchema, { minItems: 1, maxItems: 4 }) });
export type Question = Static<typeof QuestionSchema>;
export interface QuestionAnswer { question: string; selected: string[]; customText?: string }
export interface QuestionResult { status: "answered" | "cancelled" | "unavailable"; answers: QuestionAnswer[] }
const cancelled = (): QuestionResult => ({ status: "cancelled", answers: [] });

// Pi creates fresh contexts and separate jiti loaders per extension.
// A process-global queue intentionally serializes all human prompts across both tools.
const queueKey = Symbol.for("pi.local.ask-question.queue.v1");
const globalQueue = globalThis as typeof globalThis & { [queueKey]?: { tail: Promise<unknown> } };
const queue = globalQueue[queueKey] ??= { tail: Promise.resolve() };

export function validateQuestions(params: { questions: Question[] }): void {
  if (!Array.isArray(params?.questions) || params.questions.length < 1 || params.questions.length > 4) throw new Error("Provide 1–4 questions");
  if (JSON.stringify(params).length > 24000) throw new Error("Questionnaire exceeds 24000 characters");
  const unsafe = /[\u0000-\u0008\u000b-\u001f\u007f-\u009f]/;
  for (const q of params.questions) {
    if (typeof q?.question !== "string" || !q.question.trim() || q.question.length > 12000) throw new Error("Question must be nonempty text (max 12000 characters)");
    if (q.header !== undefined && (typeof q.header !== "string" || q.header.length > 120)) throw new Error("Invalid question header");
    if (q.multiSelect !== undefined && typeof q.multiSelect !== "boolean") throw new Error("multiSelect must be boolean");
    if (q.options !== undefined && (!Array.isArray(q.options) || q.options.length > 12 || q.options.some(o => typeof o?.label !== "string" || !o.label.trim() || o.label.length > 1000 || (o.description !== undefined && (typeof o.description !== "string" || o.description.length > 4000))))) throw new Error("Provide at most 12 options with nonempty labels");
    if ([q.question, q.header, ...(q.options ?? []).flatMap(o => [o.label, o.description])].some(text => text && unsafe.test(text))) throw new Error("Question text must not contain terminal control characters");
    if (new Set(q.options?.map(o => o.label)).size !== (q.options?.length ?? 0)) throw new Error("Option labels must be unique");
  }
}

async function rpcQuestion(ctx: ExtensionContext, q: Question, signal?: AbortSignal): Promise<QuestionAnswer | null> {
  const options = q.options ?? [];
  const selected = new Set<number>();
  let customText: string | undefined;
  const title = q.header ? `${q.header}: ${q.question}` : q.question;
  if (!options.length) {
    while (!signal?.aborted) {
      const text = await ctx.ui.input(title, "Enter your answer", { signal });
      if (text === undefined) return null;
      if (text.trim() && text.length <= 4000) return { question: q.question, selected: [], customText: text.trim() };
    }
    return null;
  }
  while (!signal?.aborted) {
    const rows = options.map((o, i) => `${i + 1}. ${q.multiSelect ? (selected.has(i) ? "[x] " : "[ ] ") : ""}${o.label}${o.description ? ` — ${o.description}` : ""}`);
    rows.push("Other: enter your own answer");
    if (q.multiSelect) rows.push("Done: submit selections");
    const choice = await ctx.ui.select(title, rows, { signal });
    if (choice === undefined || signal?.aborted) return null;
    const index = rows.indexOf(choice);
    if (index < 0) return null;
    if (index < options.length) {
      if (!q.multiSelect) return { question: q.question, selected: [options[index].label] };
      if (selected.has(index)) selected.delete(index); else selected.add(index);
    } else if (index === options.length) {
      const text = await ctx.ui.input(title, "Enter your answer", { signal });
      if (text === undefined || signal?.aborted) return null;
      if (!text.trim() || text.length > 4000) continue;
      customText = text.trim();
      if (!q.multiSelect) return { question: q.question, selected: [], customText };
    } else if (selected.size || customText) {
      return { question: q.question, selected: options.filter((_, i) => selected.has(i)).map(o => o.label), ...(customText ? { customText } : {}) };
    }
  }
  return null;
}

/** One shared FIFO for standalone questions and agent_ask(to: "user"). */
export async function askQuestions(ctx: ExtensionContext, params: { questions: Question[] }, signal?: AbortSignal): Promise<QuestionResult> {
  validateQuestions(params);
  if (signal?.aborted) return cancelled();
  if (!ctx.hasUI || (ctx.mode !== "tui" && ctx.mode !== "rpc")) return { status: "unavailable", answers: [] };
  let onAbort: (() => void) | undefined;
  const aborted = new Promise<QuestionResult>(resolve => {
    onAbort = () => resolve(cancelled());
    signal?.addEventListener("abort", onAbort, { once: true });
  });
  const work = queue.tail.then(async (): Promise<QuestionResult> => {
    if (signal?.aborted) return cancelled();
    if (ctx.mode === "tui") {
      const answers = await showQuestionnaire(ctx, params.questions, signal);
      return answers && !signal?.aborted ? { status: "answered", answers } : cancelled();
    }
    const answers: QuestionAnswer[] = [];
    for (let i = 0; i < params.questions.length; i++) {
      if (signal?.aborted) return cancelled();
      const answer = await rpcQuestion(ctx, params.questions[i], signal);
      if (!answer || signal?.aborted) return cancelled();
      answers.push(answer);
    }
    return { status: "answered", answers };
  });
  queue.tail = work.catch(() => undefined);
  try { return await Promise.race([work, aborted]); }
  finally { if (onAbort) signal?.removeEventListener("abort", onAbort); }
}
