import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import { CURSOR_MARKER, Editor, Key, matchesKey, truncateToWidth, visibleWidth, wrapTextWithAnsi } from "@earendil-works/pi-tui";
import type { Question, QuestionAnswer } from "./service.ts";

/** Temporarily replaces the prompt editor with a bordered questionnaire and retained drafts. */
export async function showQuestionnaire(ctx: ExtensionContext, questions: Question[], signal?: AbortSignal): Promise<QuestionAnswer[] | null> {
  let removeAbort = () => {};
  try {
    return await ctx.ui.custom<QuestionAnswer[] | null>((tui, theme, _keys, done) => {
      let tab = 0, focused = false, finished = false, error = "";
      let details = false, detailScroll = 0, detailMax = 0;
      const drafts = questions.map(q => {
        const editor = new Editor(tui, {
          borderColor: s => theme.fg("borderMuted", s),
          selectList: {
            selectedPrefix: s => theme.fg("accent", s), selectedText: s => theme.fg("accent", s),
            description: s => theme.fg("muted", s), scrollInfo: s => theme.fg("dim", s), noMatch: s => theme.fg("warning", s),
          },
        });
        editor.disableSubmit = true;
        return { editor, selected: new Set<number>(), cursor: 0, editing: !q.options?.length, custom: !q.options?.length };
      });
      const answer = (i: number): QuestionAnswer | null => {
        const q = questions[i], d = drafts[i];
        const raw = d.custom ? d.editor.getExpandedText() : "";
        const text = raw.trim();
        if (raw.length > 4000 || (!d.selected.size && !text)) return null;
        return { question: q.question, selected: (q.options ?? []).filter((_, n) => d.selected.has(n)).map(o => o.label), ...(text ? { customText: text } : {}) };
      };
      const refresh = () => {
        drafts.forEach((d, i) => { d.editor.focused = focused && i === tab && d.editing && !details; });
        tui.requestRender();
      };
      const finish = (answers: QuestionAnswer[] | null) => {
        if (finished) return;
        finished = true;
        removeAbort();
        done(answers);
      };
      const abort = () => finish(null);
      signal?.addEventListener("abort", abort, { once: true });
      removeAbort = () => signal?.removeEventListener("abort", abort);
      if (signal?.aborted) queueMicrotask(abort);
      const move = (delta: number) => { tab = (tab + delta + questions.length + 1) % (questions.length + 1); error = ""; details = false; detailScroll = 0; refresh(); };
      const next = () => {
        if (!answer(tab)) { error = "Select an answer or enter 1–4000 characters."; refresh(); return; }
        move(1);
      };
      return {
        get focused() { return focused; },
        set focused(value: boolean) { focused = value; refresh(); },
        invalidate() { drafts.forEach(d => d.editor.invalidate()); },
        handleInput(data: string) {
          if (finished) return;
          const q = questions[tab], d = drafts[tab];
          if (matchesKey(data, Key.ctrl("c"))) { finish(null); return; }
          // Tab navigation also works while editing; each question keeps its own Editor.
          if (matchesKey(data, Key.tab)) { move(1); return; }
          if (matchesKey(data, Key.shift("tab"))) { move(-1); return; }
          if (matchesKey(data, Key.ctrl("o"))) { details = !details; detailScroll = 0; refresh(); return; }
          if (details) {
            if (matchesKey(data, Key.escape)) details = false;
            else if (matchesKey(data, Key.up)) detailScroll = Math.max(0, detailScroll - 1);
            else if (matchesKey(data, Key.down)) detailScroll = Math.min(detailMax, detailScroll + 1);
            refresh();
            return;
          }
          if (matchesKey(data, Key.escape)) {
            if (d?.editing && q.options?.length) { d.editing = false; refresh(); }
            else finish(null);
            return;
          }
          if (!q) {
            if (matchesKey(data, Key.enter)) {
              const answers = questions.map((_, i) => answer(i));
              if (answers.every(a => a !== null)) finish(answers as QuestionAnswer[]);
              else { error = "Some answers are missing or exceed 4000 characters. Go back to revise."; refresh(); }
            } else if (matchesKey(data, Key.left)) move(-1);
            else if (matchesKey(data, Key.right)) move(1);
            return;
          }
          if (d.editing) {
            if (matchesKey(data, Key.ctrl("s"))) { next(); return; }
            if (matchesKey(data, Key.enter)) d.editor.insertTextAtCursor("\n");
            else d.editor.handleInput(data);
            error = "";
            refresh();
            return;
          }
          if (matchesKey(data, Key.left)) { move(-1); return; }
          if (matchesKey(data, Key.right)) { move(1); return; }
          const options = q.options ?? [];
          if (matchesKey(data, Key.up)) d.cursor = Math.max(0, d.cursor - 1);
          else if (matchesKey(data, Key.down)) d.cursor = Math.min(options.length + 1, d.cursor + 1);
          else if (matchesKey(data, Key.enter) || matchesKey(data, Key.space)) {
            if (d.cursor < options.length) {
              if (!q.multiSelect) { d.selected.clear(); d.selected.add(d.cursor); d.custom = false; next(); return; }
              if (d.selected.has(d.cursor)) d.selected.delete(d.cursor); else d.selected.add(d.cursor);
            } else if (d.cursor === options.length) {
              d.editing = true; d.custom = true;
              if (!q.multiSelect) d.selected.clear();
            } else { next(); return; }
          }
          error = "";
          refresh();
        },
        render(width: number): string[] {
          const height = Math.max(1, Math.min(24, tui.terminal.rows));
          if (width < 1) return [];
          if (width < 6 || height < 8) return [truncateToWidth("Window too small; resize or Ctrl+C to cancel", width)].slice(0, height);
          const inner = width - 4;
          const q = questions[tab], d = drafts[tab];
          const title = q ? `Question ${tab + 1}/${questions.length}${q.header ? ` · ${q.header.replace(/[\r\n\t]/g, " ")}` : ""}` : "Review and submit";
          const tabs = [...questions.map((_, i) => `${i === tab ? "▶" : ""}${i + 1}${answer(i) ? "✓" : "○"}`), `${tab === questions.length ? "▶" : ""}Submit`].join("  ");
          const head = [theme.fg("accent", title), theme.fg("accent", tabs)];
          const foot = [
            theme.fg(error ? "warning" : "dim", error || "Tab next · Shift+Tab previous · Ctrl+C cancel"),
            theme.fg("dim", details ? "↑↓ scroll · Ctrl+O / Esc back" : d?.editing ? "Enter newline · Ctrl+S next · Ctrl+O details" : q ? "↑↓ navigate · Enter select · Ctrl+O details · Esc cancel" : "Enter submit · Shift+Tab revise · Ctrl+O details"),
          ];
          const budget = height - head.length - foot.length - 2;
          const body: string[] = [];
          const one = (s: string) => truncateToWidth(s.replace(/[\r\n\t]/g, " "), inner);
          if (details) {
            const text = q
              ? [q.question, ...(q.options ?? []).map((o, i) => `${i + 1}. ${o.label}${o.description ? `\n${o.description}` : ""}`)].join("\n\n")
              : questions.map((question, i) => { const a = answer(i); return `${i + 1}. ${question.question}\n${a ? [...a.selected, a.customText].filter(Boolean).join("\n") : "Incomplete"}`; }).join("\n\n");
            const full = wrapTextWithAnsi(text, inner);
            detailMax = Math.max(0, full.length - budget);
            detailScroll = Math.min(detailScroll, detailMax);
            body.push(...full.slice(detailScroll, detailScroll + budget));
          } else if (!q) {
            questions.forEach((question, i) => {
              const a = answer(i);
              body.push(one(`${i + 1}. ${question.header || question.question}: ${a ? [...a.selected, a.customText].filter(Boolean).join("; ") : "Incomplete"}`));
            });
            body.push(questions.every((_, i) => answer(i)) ? "✓ Answers ready. Press Enter to submit." : "Go back to complete the unanswered questions." );
          } else {
            body.push(...wrapTextWithAnsi(q.question, inner).slice(0, Math.min(2, budget - 1)));
            const room = budget - body.length;
            if (d.editing) {
              const rendered = d.editor.render(inner);
              // Keep the IME cursor visible even when Pi's editor viewport exceeds this panel.
              const cursor = rendered.findIndex(line => line.includes(CURSOR_MARKER));
              const start = Math.max(0, Math.min(rendered.length - room, cursor - room + 1));
              body.push(...rendered.slice(start, start + room));
            } else {
              const options = q.options ?? [];
              const rows = [...options.map((o, i) => `${d.selected.has(i) ? "[✓]" : "[ ]"} ${o.label}${o.description ? ` — ${o.description}` : ""}`),
                `Custom text (multiline)${d.custom && d.editor.getExpandedText().trim() ? " ✓" : ""}`, "Next / Review answers"];
              const start = Math.max(0, Math.min(d.cursor - Math.floor(room / 2), rows.length - room));
              rows.slice(start, start + room).forEach((row, n) => body.push(theme.fg(start + n === d.cursor ? "accent" : "text", one(`${start + n === d.cursor ? "▶" : " "} ${row}`))));
            }
          }
          const border = (left: string, right: string) => theme.fg("borderAccent", left + "─".repeat(width - 2) + right);
          const lines = [...head, ...body.slice(0, budget), ...foot].map(line => {
            const text = truncateToWidth(line, inner);
            return theme.fg("borderAccent", "│") + " " + text + " ".repeat(Math.max(0, inner - visibleWidth(text))) + " " + theme.fg("borderAccent", "│");
          });
          return [border("╭", "╮"), ...lines, border("╰", "╯")];
        },
      };
    }, { overlay: false }) ?? null;
  } finally { removeAbort(); }
}
