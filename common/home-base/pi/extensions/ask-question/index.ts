import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { keyText } from "@earendil-works/pi-coding-agent";
import { Container, Text } from "@earendil-works/pi-tui";
import { askQuestions, QuestionsSchema, type QuestionResult } from "./service.ts";

// Display only: preserve the original structured answers in content/details.
function displayText(text: string): string {
  return text.replace(/[\u0000-\u0008\u000b-\u001f\u007f-\u009f]/g, "").replace(/\t/g, "  ");
}

function answerSummary(result: QuestionResult, expanded: boolean): string {
  if (result.status === "cancelled") return "已取消 · 未送出任何答案，不代表同意。";
  if (result.status === "unavailable") return "無法作答 · 目前沒有可用的人類問答介面，不代表同意。";
  const preview = (text: string) => {
    const clean = displayText(text);
    if (expanded) return clean;
    const chars = Array.from(clean.replace(/\s+/g, " "));
    return chars.length > 100 ? `${chars.slice(0, 100).join("")}…` : chars.join("");
  };
  return result.answers.map((answer, i) => [
    `${i + 1}. ${preview(answer.question)}`,
    ...answer.selected.map(label => `  ✓ ${preview(label)}`),
    ...(answer.customText ? [`  自訂：${preview(answer.customText)}`] : []),
  ].join("\n")).join("\n\n");
}

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
      if (ctx.hasUI) ctx.ui.notify(answerSummary(result, false), "info");
    },
  });
  pi.registerTool({
    name: "ask_user_question",
    label: "Ask User",
    description: "Ask the human 1–4 questions instead of guessing. Supports single/multiple choices and custom text. Write questions, headers, option labels and descriptions in Traditional Chinese by default unless the user requests another language. Cancellation is not approval; do not infer an answer when unavailable or cancelled.",
    parameters: QuestionsSchema,
    renderCall() {
      return new Container();
    },
    renderResult(result, { expanded, isPartial }, theme) {
      if (isPartial) return new Text(theme.fg("muted", "等待使用者作答…"), 0, 0);
      const details = result.details as QuestionResult | undefined;
      if (!details || !["answered", "cancelled", "unavailable"].includes(details.status)) {
        const text = result.content.filter(part => part.type === "text").map(part => part.text).join("\n");
        return new Text(theme.fg("error", displayText(text || "問答結果無法顯示。")), 0, 0);
      }
      const text = answerSummary(details, expanded);
      const hint = details.status === "answered" && !expanded ? `\n\n${theme.fg("dim", `${keyText("app.tools.expand")} 展開完整問答`)}` : "";
      return new Text((details.status === "answered" ? text : theme.fg("warning", text)) + hint, 0, 0);
    },
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
