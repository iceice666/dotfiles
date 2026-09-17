import { afterAll, expect, test } from 'bun:test';
import { loadExtensions } from './sdk.ts';
const saved = process.env.PI_TEAM_AGENT;
delete process.env.PI_TEAM_AGENT;
afterAll(() => { if (saved !== undefined) process.env.PI_TEAM_AGENT = saved; });
const tick = () => new Promise(resolve => setTimeout(resolve, 0));
async function setup() {
  const listeners = new Map<string, Set<(data: any) => void>>();
  const events = {
    emit(name: string, data?: any) { for (const listener of listeners.get(name) ?? []) listener(data); },
    on(name: string, listener: (data: any) => void) {
      if (!listeners.has(name)) listeners.set(name, new Set());
      listeners.get(name)!.add(listener);
      return () => { listeners.get(name)!.delete(listener); };
    },
  };
  const loaded = await loadExtensions([`${import.meta.dir}/../index.ts`, `${import.meta.dir}/../../ask-question/index.ts`], process.cwd(), events);
  expect(loaded.errors).toEqual([]);
  const team = loaded.extensions[0], standalone = loaded.extensions[1];
  const views: any[] = [];
  const widgets: any[] = [];
  const statuses: any[] = [];
  // No sessionManager: direct parent questions must not construct Team/broker.
  const ctx: any = { mode: 'tui', hasUI: true, ui: {
    setStatus: (...args: any[]) => statuses.push(args),
    setWidget: (...args: any[]) => widgets.push(args),
    custom: (factory: any) => new Promise(resolve => views.push(factory({ requestRender() {}, terminal: { rows: 24, columns: 80 } }, { fg: (_: string, text: string) => text, bg: (_: string, text: string) => text, bold: (text: string) => text }, {}, resolve))),
  } };
  const call = (args: any, signal?: AbortSignal) => team.tools.get('agent_ask')!.definition.execute('id', args, signal, undefined, ctx);
  const ask = (question: string) => standalone.tools.get('ask_user_question')!.definition.execute('id', { questions: [{ question }] }, undefined, undefined, ctx);
  const shutdown = async () => { for (const handler of team.handlers.get('session_shutdown') ?? []) await handler({} as any, ctx); };
  return { ctx, views, widgets, statuses, call, ask, shutdown, team, events };
}

test('team publishes empty state on request and shutdown without widgets or shortcuts', async () => {
  const s = await setup();
  const states: any[] = [];
  s.events.on('agent-team:state', state => states.push(state));
  for (const handler of s.team.handlers.get('session_start') ?? []) await handler({} as any, s.ctx);
  s.events.emit('agent-team:request-state');
  expect(states).toEqual([{ agents: [] }]);
  expect(s.team.shortcuts.size).toBe(0);
  await s.shutdown();
  expect(states).toEqual([{ agents: [] }, { agents: [] }]);
  s.events.emit('agent-team:request-state');
  expect(states).toHaveLength(2);
  expect(s.widgets).toEqual([]);
  expect(s.statuses).toEqual([]);
});

test('all registered team tools provide display-only renderers', async () => {
  const s = await setup();
  for (const { definition } of s.team.tools.values()) {
    expect(typeof definition.renderCall).toBe('function');
    expect(typeof definition.renderResult).toBe('function');
  }
  expect(s.team.messageRenderers.has('agent-team')).toBe(true);
  await s.shutdown();
});

test('parent to:user directly awaits shared UI and returns structured selection', async () => {
  const s = await setup();
  const pending = s.call({ to: 'user', question: 'Choose', options: [{ label: 'A' }, { label: 'B' }] });
  await tick(); expect(s.views).toHaveLength(1);
  s.views[0].handleInput('\x1b[B'); s.views[0].handleInput('\r');
  s.views[0].handleInput('\r'); // Explicit final review submission.
  const result: any = await pending;
  expect(JSON.parse(result.content[0].text)).toEqual({ status: 'answered', answers: [{ question: 'Choose', selected: ['B'] }] });
  await s.shutdown();
});

test('agent_ask and ask_user_question serialize across independent extension loaders', async () => {
  const s = await setup();
  const first = s.ask('Standalone');
  const second = s.call({ to: 'user', question: 'Team' });
  await tick(); expect(s.views).toHaveLength(1);
  s.views[0].handleInput('\x1b'); await first;
  await tick(); expect(s.views).toHaveLength(2);
  s.views[1].handleInput('Human'); s.views[1].handleInput('\x13'); // Ctrl+S saves multiline draft.
  s.views[1].handleInput('\r'); // Explicit final review submission.
  const result: any = await second;
  expect(JSON.parse(result.content[0].text).answers[0].customText).toBe('Human');
  await s.shutdown();
});

test('parent shutdown cancels queued and active UI; unavailable is explicit', async () => {
  const s = await setup();
  const first = s.call({ to: 'user', question: 'Active' });
  const second = s.call({ to: 'user', question: 'Queued' });
  await tick(); await s.shutdown();
  for (const pending of [first, second]) {
    const result: any = await pending;
    expect(JSON.parse(result.content[0].text)).toEqual({ status: 'cancelled', answers: [] });
  }
  await tick(); expect(s.views).toHaveLength(1);
  const headless = await setup(); headless.ctx.mode = 'print'; headless.ctx.hasUI = false;
  const result: any = await headless.call({ to: 'user', question: 'Q' });
  expect(JSON.parse(result.content[0].text)).toEqual({ status: 'unavailable', answers: [] });
});


test('team defaults to text status; attach is TUI guarded and rejects unknown workers', async () => {
  const s = await setup();
  const notices: string[] = [];
  s.ctx.ui.notify = (message: string) => notices.push(message);
  for (const handler of s.team.handlers.get('session_start') ?? []) await handler({} as any, s.ctx);
  await s.team.commands.get('team')!.handler('', s.ctx);
  expect(notices.at(-1)).toContain('No team running');
  await s.team.commands.get('team')!.handler('panel', s.ctx);
  expect(notices.at(-1)).toContain('Usage:');
  s.events.emit('agent-team:attach', { name: 'missing' });
  await tick();
  expect(notices.at(-1)).toContain('Unknown agent');
  s.ctx.mode = 'rpc';
  await s.team.commands.get('team')!.handler('attach missing', s.ctx);
  expect(notices.at(-1)).toContain('TUI');
  expect(s.views).toEqual([]);
  await s.shutdown();
  const count = notices.length;
  s.events.emit('agent-team:attach', { name: 'missing' });
  await tick();
  expect(notices).toHaveLength(count);
});
