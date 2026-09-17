import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { askQuestions, QuestionsSchema } from "./service.ts";

export default function (pi: ExtensionAPI) {
  let lifetime = new AbortController();
  const isWorker = () => Boolean(process.env.PI_TEAM_AGENT && process.env.PI_TEAM_URL && process.env.PI_TEAM_TOKEN);
  pi.on("session_start", () => {
    lifetime.abort();
    lifetime = new AbortController();
    if (isWorker()) pi.setActiveTools(pi.getActiveTools().filter(name => name !== "ask_user_question"));
  });
  pi.on("session_shutdown", () => lifetime.abort());
  pi.registerCommand("ask-question", {
    description: "Preview the question panel (no model call)",
    async handler(_args, ctx) {
      if (isWorker()) return;
      const result = await askQuestions(ctx, { questions: [{ question: "Choose a test answer or enter your own text.", options: [{ label: "Works as expected" }, { label: "Try again later" }] }] }, lifetime.signal);
      if (ctx.hasUI) ctx.ui.notify(JSON.stringify(result), "info");
    },
  });
  pi.registerTool({
    name: "ask_user_question",
    label: "Ask User",
    description: "Ask the human 1–4 questions instead of guessing. Supports single/multiple choices and custom text. Write questions, headers, option labels and descriptions in Traditional Chinese by default unless the user requests another language. Cancellation is not approval; do not infer an answer when unavailable or cancelled.",
    parameters: QuestionsSchema,
    async execute(_id, params, signal, _update, ctx) {
      if (isWorker()) return { content: [{ type: "text", text: 'Human UI unavailable in workers. Use agent_ask with to: "user".' }], details: { status: "unavailable", answers: [] } };
      const combined = signal ? AbortSignal.any([signal, lifetime.signal]) : lifetime.signal;
      const result = await askQuestions(ctx, params, combined);
      const text = JSON.stringify(result);
      // Keep tool content below Pi's 50KB ceiling; full structured details remain available.
      const summary = Buffer.byteLength(text, "utf8") > 48000 ? `${text.slice(0, 10000)}\n[Summary truncated; full answers in details]` : text;
      return { content: [{ type: "text", text: summary }], details: result };
    },
  });
}
