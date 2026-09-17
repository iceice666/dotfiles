import { afterAll, expect, test } from "bun:test";
const workerEnv = process.env.PI_TEAM_AGENT;
delete process.env.PI_TEAM_AGENT;
afterAll(() => { if (workerEnv !== undefined) process.env.PI_TEAM_AGENT = workerEnv; });
import { loadExtensions } from "../../agent-team/tests/sdk.ts";
import { visibleWidth } from "@earendil-works/pi-tui";

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
  return { ctx, views, terminal, shutdown: async () => { for (const handler of loaded.extensions[0].handlers.get("session_shutdown") ?? []) await handler({} as any, ctx); }, call: (questions: any[], signal?: AbortSignal) => tool.execute("test", { questions }, signal, undefined, ctx) };
}
const tick = () => new Promise(resolve => setTimeout(resolve, 0));

test("single selection and narrow width / IME focus", async () => {
  const s = await setup();
  const result = s.call([{ question: "选什么？", options: [{ label: "甲" }, { label: "乙" }] }]);
  await tick();
  const view = s.views[0];
  for (const width of [1, 2, 10, 80]) expect(view.render(width).every((line: string) => visibleWidth(line) <= width)).toBe(true);
  view.handleInput("\x1b[B"); view.handleInput("\r"); view.handleInput("\r");
  expect((await result).details).toEqual({ status: "answered", answers: [{ question: "选什么？", selected: ["乙"] }] });
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
