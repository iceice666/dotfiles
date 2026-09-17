import { afterAll, expect, test } from "bun:test";
const workerEnv = process.env.PI_TEAM_AGENT;
delete process.env.PI_TEAM_AGENT;
afterAll(() => { if (workerEnv !== undefined) process.env.PI_TEAM_AGENT = workerEnv; });
import { loadExtensions } from "../../agent-team/tests/sdk.ts";
import { visibleWidth, wrapTextWithAnsi } from "@earendil-works/pi-tui";

async function setup(mode = "tui") {
  const loaded = await loadExtensions([`${import.meta.dir}/../index.ts`], process.cwd());
  expect(loaded.errors).toEqual([]);
  const tool = loaded.extensions[0].tools.get("ask_user_question")!.definition;
  const views: any[] = [];
  const theme = { fg: (_: string, s: string) => s };
  const terminal = { rows: 24, columns: 80 };
  const ctx: any = { mode, hasUI: mode !== "print", ui: {
    custom: (factory: any, options: any) => new Promise(resolve => {
      expect(options.overlay).toBe(false); // Replace the prompt editor, never cover the transcript.
      views.push(factory({ requestRender() {}, terminal }, theme, {}, resolve));
    }),
  } };
  return { tool, ctx, views, terminal, shutdown: async () => { for (const handler of loaded.extensions[0].handlers.get("session_shutdown") ?? []) await handler({} as any, ctx); }, call: (questions: any[], signal?: AbortSignal) => tool.execute("test", { questions }, signal, undefined, ctx) };
}
const tick = () => new Promise(resolve => setTimeout(resolve, 0));
const renderTheme: any = { fg: (_: string, text: string) => text, bold: (text: string) => text };

test("transcript renders readable answers without changing model JSON", async () => {
  const s = await setup("rpc");
  s.ctx.ui.input = async () => "第一行\n第二行";
  const result = await s.call([{ question: "要先做哪一步？" }]);
  expect(JSON.parse(result.content[0].text)).toEqual(result.details);
  const call = s.tool.renderCall!({ questions: [{ question: "要先做哪一步？" }] }, renderTheme, {} as any);
  expect(call.render(80)).toEqual([]);
  for (const expanded of [false, true]) {
    const component = s.tool.renderResult!(result, { expanded, isPartial: false }, renderTheme, {} as any);
    const text = component.render(80).join("\n");
    expect(text).not.toContain("已回答");
    expect(text).toStartWith("1. 要先做哪一步？");
    expect(text).toContain("1. 要先做哪一步？");
    expect(text).toContain("自訂：第一行");
    expect(text).not.toContain('"status"');
    expect(text.includes("展開完整問答")).toBe(!expanded);
    for (const width of [2, 10, 40]) expect(component.render(width).every(line => visibleWidth(line) <= width)).toBe(true);
  }
});

test("transcript supports multiple selections, bounded previews and complete expanded answers", async () => {
  const s = await setup();
  const details = { status: "answered", answers: [
    { question: "長問題".repeat(100), selected: ["選項甲", "選項乙"], customText: "自訂\u001b[2J\n答案結尾" },
    { question: "第二題", selected: ["保留現況"] },
  ] };
  const render = (expanded: boolean) => s.tool.renderResult!({ content: [], details }, { expanded, isPartial: false }, renderTheme, {} as any).render(80).join("\n");
  const collapsed = render(false);
  expect(collapsed).not.toContain("已回答");
  expect(collapsed).toStartWith("1. 長問題");
  expect(collapsed).toContain("✓ 選項甲");
  expect(collapsed).toContain("✓ 選項乙");
  expect(collapsed).toContain("2. 第二題");
  expect(collapsed).toContain("…");
  expect(collapsed).not.toContain("\u001b");
  expect(render(true).replace(/\s/g, "")).toContain("長問題".repeat(100));
  expect(render(true)).toContain("答案結尾");
});

test("transcript distinguishes cancellation, unavailable, progress and tool errors", async () => {
  const s = await setup();
  for (const status of ["cancelled", "unavailable"]) {
    const text = s.tool.renderResult!({ content: [], details: { status, answers: [] } }, { expanded: false, isPartial: false }, renderTheme, {} as any).render(80).join("\n");
    expect(text).toContain(status === "cancelled" ? "已取消" : "無法作答");
    expect(text).toContain("不代表同意");
    expect(text).not.toContain("已回答");
  }
  const render = (isPartial: boolean) => s.tool.renderResult!({ content: [{ type: "text", text: "Invalid request" }] }, { expanded: false, isPartial }, renderTheme, {} as any).render(80).join("\n");
  expect(render(true)).toContain("等待使用者作答");
  expect(render(false)).toContain("Invalid request");
});

test("single selection and narrow width / IME focus", async () => {
  const s = await setup();
  const result = s.call([{ question: "选什么？", options: [{ label: "甲" }, { label: "乙" }] }]);
  await tick();
  const view = s.views[0];
  for (const width of [1, 2, 10, 80]) expect(view.render(width).every((line: string) => visibleWidth(line) <= width)).toBe(true);
  view.handleInput("\x1b[B"); view.handleInput("\r"); view.handleInput("\r");
  expect((await result).details).toEqual({ status: "answered", answers: [{ question: "选什么？", selected: ["乙"] }] });
});

test("long questions wrap beyond two lines with choices and a focused editor", async () => {
  const s = await setup();
  const question = "請確認這個比較長的問題是否能夠完整換行顯示，而不是只留下前兩行。".repeat(3) + "\n問題結尾";
  for (const options of [[{ label: "同意" }], undefined]) {
    const result = s.call([{ question, options }]);
    await tick();
    const v = s.views.at(-1);
    v.focused = true;
    for (const width of [40, 60, 80]) {
      const wrapped = wrapTextWithAnsi(question, width - 4);
      expect(wrapped.length).toBeGreaterThan(2);
      const lines = v.render(width);
      for (const line of wrapped) expect(lines.join("\n")).toContain(line);
      expect(lines.length).toBeLessThanOrEqual(24);
      expect(lines.every((line: string) => visibleWidth(line) <= width)).toBe(true);
      expect(lines.join("\n")).toContain(options ? "同意" : "\x1b_pi:c\x07");
    }
    v.handleInput("\x03");
    expect((await result).details.status).toBe("cancelled");
  }
});

test("overflowing questions advertise full details and reflow after resizing", async () => {
  const s = await setup();
  const question = "問題開頭\n" + "長問題內容".repeat(100) + "\n問題結尾";
  const result = s.call([{ question, options: [{ label: "同意" }] }]);
  await tick();
  const v = s.views[0];
  for (const rows of [8, 12, 24]) {
    s.terminal.rows = rows;
    const lines = v.render(40);
    expect(lines.join("\n")).toContain("Ctrl+O: full question");
    expect(lines.join("\n")).toContain("同意");
    expect(lines.length).toBeLessThanOrEqual(rows);
  }
  s.terminal.rows = 24;
  v.handleInput("\x0f");
  v.render(40);
  for (let i = 0; i < 100; i++) v.handleInput("\x1b[B");
  expect(v.render(40).join("\n")).toContain("問題結尾");
  v.handleInput("\x1b");
  const wide = v.render(120);
  expect(wide.join("\n")).toContain("問題結尾");
  expect(wide.join("\n")).not.toContain("Ctrl+O: full question");
  v.handleInput("\r"); v.handleInput("\r");
  expect((await result).details.answers[0].selected).toEqual(["同意"]);
});

test("multiple choices plus custom answer", async () => {
  const s = await setup();
  const result = s.call([{ question: "Pick", multiSelect: true, options: [{ label: "A" }, { label: "B" }] }]);
  await tick();
  const v = s.views[0];
  v.handleInput(" "); v.handleInput("\x1b[B"); v.handleInput(" ");
  v.handleInput("\x1b[B"); v.handleInput("\r"); v.focused = true;
  v.handleInput("自定"); v.handleInput("\x13"); v.handleInput("\r");
  expect((await result).details.answers[0]).toEqual({ question: "Pick", selected: ["A", "B"], customText: "自定" });
});

test("queued abort does not open a prompt; active abort releases FIFO", async () => {
  const s = await setup();
  const a = new AbortController(), b = new AbortController();
  const first = s.call([{ question: "first" }], a.signal);
  const second = s.call([{ question: "second" }], b.signal);
  const third = s.call([{ question: "third" }]);
  await tick();
  expect(s.views).toHaveLength(1);
  b.abort(); expect((await second).details.status).toBe("cancelled");
  a.abort(); expect((await first).details.status).toBe("cancelled");
  await tick(); expect(s.views).toHaveLength(2);
  s.views[1].handleInput("answer"); s.views[1].handleInput("\x13"); s.views[1].handleInput("\r");
  expect((await third).details.answers[0].customText).toBe("answer");
});

test("independent extension loader instances share queue", async () => {
  const a = await setup(), b = await setup();
  const p = a.call([{ question: "a" }]);
  const q = b.call([{ question: "b" }]);
  await tick(); expect(a.views).toHaveLength(1); expect(b.views).toHaveLength(0);
  a.views[0].handleInput("\x1b"); await p;
  await tick(); expect(b.views).toHaveLength(1);
  b.views[0].handleInput("\x1b"); await q;
});

test("RPC fallback preserves option descriptions, multiselect and custom text", async () => {
  const s = await setup("rpc");
  let step = 0;
  s.ctx.ui.select = async (_title: string, rows: string[]) => rows[[0, 2, 3][step++]];
  s.ctx.ui.input = async () => "other";
  const r = await s.call([{ question: "RPC", multiSelect: true, options: [{ label: "A", description: "aa" }, { label: "B" }] }]);
  expect(r.details.answers[0]).toEqual({ question: "RPC", selected: ["A"], customText: "other" });
  expect(s.views).toHaveLength(0);
});

test("noninteractive unavailable, invalid requests rejected, cancellation discards partial answers", async () => {
  const headless = await setup("print");
  expect((await headless.call([{ question: "q" }])).details.status).toBe("unavailable");
  await expect(headless.call([])).rejects.toThrow();
  await expect(headless.call([{ question: "\x1b[2J" }])).rejects.toThrow();
  await expect(headless.call([{ question: "q", options: [{ label: "A" }, { label: "A" }] }])).rejects.toThrow();
  const s = await setup("rpc"); let n = 0;
  s.ctx.ui.input = async () => n++ ? undefined : "first answer";
  expect((await s.call([{ question: "first" }, { question: "second" }])).details).toEqual({ status: "cancelled", answers: [] });
});


test("shutdown cancels active and queued dialogs; long text fits 24 rows", async () => {
  const s = await setup();
  const p = s.call([{ question: "字".repeat(1000), options: Array.from({length: 12}, (_, i) => ({label: `${i}長`.repeat(100), description: "說明".repeat(100)})) }]);
  const q = s.call([{ question: "queued" }]);
  await tick();
  expect(s.views[0].render(20).length).toBeLessThanOrEqual(24);
  await s.shutdown();
  expect((await p).details.status).toBe("cancelled");
  expect((await q).details.status).toBe("cancelled");
  expect(s.views).toHaveLength(1);
});

test("tabs retain multiline drafts and choices; only complete review can submit", async () => {
  const s = await setup();
  const result = s.call([{ question: "文字" }, { question: "選項", options: [{ label: "甲" }, { label: "乙" }] }]);
  let settled = false;
  void result.then(() => { settled = true; });
  await tick();
  const v = s.views[0];
  v.focused = true;
  v.handleInput("第一行"); v.handleInput("\r"); v.handleInput("第二行");
  expect(v.render(80).join("\n")).toContain("第一行");
  expect(v.render(80).join("\n")).toContain("第二行");
  expect(v.render(80).join("\n")).toContain("\x1b_pi:c\x07");
  v.handleInput("\t"); v.handleInput("\t"); v.handleInput("\r");
  await tick(); expect(settled).toBe(false);
  expect(v.render(80).join("\n")).toContain("Some answers are missing");
  v.handleInput("\x1b[Z"); v.handleInput("\r"); // choose 甲, review
  v.handleInput("\x1b[Z"); v.handleInput("\x1b[B"); v.handleInput("\r"); // revise to 乙
  v.handleInput("\t"); // cycle review -> first editor
  expect(v.render(80).join("\n")).toContain("第二行");
  v.handleInput("修訂"); v.handleInput("\x13"); v.handleInput("\t");
  await tick(); expect(settled).toBe(false);
  v.handleInput("\r");
  expect((await result).details.answers).toEqual([
    { question: "文字", selected: [], customText: "第一行\n第二行修訂" },
    { question: "選項", selected: ["乙"] },
  ]);
  expect(s.views).toHaveLength(1);
});

test("editor validation, expanded multiline paste, cancellation discards drafts", async () => {
  const s = await setup();
  const result = s.call([{ question: "文字" }]);
  await tick(); const v = s.views[0];
  v.handleInput("\x13");
  expect(v.render(80).join("\n")).toContain("1–4000");
  v.handleInput("\x1b[200~" + "字".repeat(4001) + "\x1b[201~");
  v.handleInput("\x13");
  expect(v.render(80).join("\n")).toContain("1–4000");
  v.handleInput("\x03");
  expect((await result).details).toEqual({ status: "cancelled", answers: [] });
  const next = s.call([{ question: "貼上" }]);
  await tick(); const w = s.views[1];
  const text = Array.from({ length: 20 }, (_, i) => `第${i}行`).join("\n");
  w.handleInput("\x1b[200~" + text + "\x1b[201~");
  w.handleInput("\x13"); w.handleInput("\r");
  expect((await next).details.answers[0].customText).toBe(text);
});

test("bounded bordered panel, scrollable full details, focus survives resizing", async () => {
  const s = await setup();
  const result = s.call([{ question: "開頭\n" + "中間\n".repeat(40) + "問題結尾", options: [{ label: "選項", description: "完整說明結尾" }] }]);
  await tick(); const v = s.views[0];
  expect(v.render(80)[0]).toStartWith("╭");
  v.handleInput("\x0f");
  for (let n = 0; n < 100; n++) v.handleInput("\x1b[B");
  expect(v.render(80).join("\n")).not.toContain("完整說明結尾"); // first render establishes scroll range
  for (let n = 0; n < 100; n++) v.handleInput("\x1b[B");
  expect(v.render(80).join("\n")).toContain("完整說明結尾");
  v.handleInput("\x1b"); // exits details, not questionnaire
  v.handleInput("\x1b[B"); v.handleInput("\r"); v.focused = true;
  v.handleInput("中文");
  for (const rows of [1, 7, 8, 12, 24, 40]) {
    s.terminal.rows = rows;
    for (const width of [1, 2, 4, 12, 80]) {
      const lines = v.render(width);
      expect(lines.length).toBeLessThanOrEqual(rows);
      expect(lines.every((line: string) => visibleWidth(line) <= width)).toBe(true);
    }
  }
  s.terminal.rows = 24;
  v.handleInput("\x13"); v.handleInput("\r");
  expect((await result).details.answers[0].customText).toBe("中文");
});

test("team workers cannot invoke standalone user UI", async () => {
  const previous = [process.env.PI_TEAM_AGENT, process.env.PI_TEAM_URL, process.env.PI_TEAM_TOKEN];
  Object.assign(process.env, { PI_TEAM_AGENT: "test", PI_TEAM_URL: "http://localhost", PI_TEAM_TOKEN: "test" });
  try {
    const s = await setup();
    expect((await s.call([{ question: "q" }])).details.status).toBe("unavailable");
    expect(s.views).toHaveLength(0);
  } finally {
    ["PI_TEAM_AGENT", "PI_TEAM_URL", "PI_TEAM_TOKEN"].forEach((key, i) => { if (previous[i] === undefined) delete process.env[key]; else process.env[key] = previous[i]; });
  }
});
