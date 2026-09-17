import { expect, test } from 'bun:test';
import { visibleWidth } from '@earendil-works/pi-tui';
import statusLine, { TeamStatus } from '../../status-line.ts';

const theme: any = { fg: (_: string, text: string) => text };
const agents = [{ name: 'alpha', status: 'running' }, { name: 'beta', status: 'idle' }];

test('footer event bridge, editor wrapping, prompt isolation and shutdown cleanup', async () => {
  const handlers = new Map<string, Function>();
  const listeners = new Map<string, Function>();
  let footer: any, factory: any;
  let text = '', passed = '', attached = '';
  const editor = { getText: () => text, handleInput: (data: string) => { passed += data; } };
  const originalInput = editor.handleInput;
  const previous = () => editor; factory = previous;
  const pi: any = {
    on: (name: string, handler: Function) => handlers.set(name, handler),
    events: {
      on: (name: string, handler: Function) => { listeners.set(name, handler); return () => listeners.delete(name); },
      emit: (name: string, data: any) => {
        if (name === 'agent-team:attach') attached = data.name;
        listeners.get(name)?.(data);
      },
    },
    exec: async () => ({ code: 0, stdout: '', killed: false }),
    getThinkingLevel: () => 'high',
  };
  const ctx: any = { mode: 'tui', cwd: '/tmp', getContextUsage: () => undefined, ui: {
    getEditorComponent: () => factory,
    setEditorComponent: (value: any) => { factory = value; },
    setFooter: (make: any) => { footer = make({ requestRender() {} }, theme, {
      onBranchChange: () => () => {}, getExtensionStatuses: () => new Map([['other', 'other status']]),
    }); },
  } };
  statusLine(pi); handlers.get('session_start')!({}, ctx);
  try {
    const wrapped = factory({ requestRender() {} }, theme, {});
    pi.events.emit('agent-team:state', { agents });
    expect(footer.render(100).slice(1)).toEqual(['· alpha · running', '· beta · idle', 'other status']);
    wrapped.handleInput('\x1b[B'); wrapped.handleInput('\r');
    expect(attached).toBe('alpha'); expect(passed).toBe('');
    text = 'draft'; wrapped.handleInput('\x1b[B'); expect(passed).toBe('\x1b[B');
    text = ''; wrapped.handleInput('\x1b[B'); handlers.get('ui_prompt_start')!();
    expect(footer.render(100).join('\n')).not.toContain('›');
    pi.events.emit('agent-team:state', { agents: [] });
    expect(footer.render(100)).toHaveLength(2);
  } finally { handlers.get('session_shutdown')!(); }
  expect(factory).toBe(previous); expect(listeners.size).toBe(0);
  expect(editor.handleInput).toBe(originalInput);
  handlers.get('session_start')!({}, ctx);
  factory({ requestRender() {} }, theme, {});
  handlers.get('session_shutdown')!();
  expect(editor.handleInput).toBe(originalInput);
});

test('one row per live worker, including idle; terminal states disappear', () => {
  const state = new TeamStatus();
  state.update([...agents, ...['failed', 'stopped', 'exited'].map(status => ({ name: status, status }))]);
  expect(state.render(80, theme)).toEqual(['· alpha · running', '· beta · idle']);
  state.update([]);
  expect(state.render(80, theme)).toEqual([]);
});

test('empty editor down selects, arrows navigate, enter attaches without sending input', () => {
  const state = new TeamStatus(); state.update(agents);
  const attached: string[] = [];
  const key = (data: string, text = '') => state.input(data, text, name => attached.push(name));
  expect(key('\x1b[A')).toBe(false);
  expect(key('\x1b[B', 'draft')).toBe(false);
  expect(key('\x1b[B')).toBe(true); expect(state.selected).toBe('alpha');
  expect(key('\x1b[B')).toBe(true); expect(state.selected).toBe('beta');
  key('\x1b[B'); expect(state.selected).toBe('beta');
  key('\x1b[A'); expect(state.selected).toBe('alpha');
  expect(key('\r')).toBe(true); expect(attached).toEqual(['alpha']);
  expect(state.selected).toBeUndefined();
  expect(key('\r')).toBe(false);
});

test('escape and up at first row return to editor; typing passes through', () => {
  const state = new TeamStatus(); state.update(agents);
  const key = (data: string) => state.input(data, '', () => {});
  key('\x1b[B'); expect(key('\x1b')).toBe(true); expect(state.selected).toBeUndefined();
  key('\x1b[B'); expect(key('\x1b[A')).toBe(true); expect(state.selected).toBeUndefined();
  key('\x1b[B'); expect(key('x')).toBe(false); expect(state.selected).toBeUndefined();
});

test('selection survives updates by name and clears when selected worker exits', () => {
  const state = new TeamStatus(); state.update(agents);
  state.input('\x1b[B', '', () => {});
  state.update([...agents].reverse()); expect(state.selected).toBe('alpha');
  state.update([{ name: 'alpha', status: 'stopped' }, agents[1]]);
  expect(state.selected).toBeUndefined();
  expect(state.input('\r', '', () => { throw Error('stale attachment'); })).toBe(false);
});

test('rows sanitize controls and fit narrow and unicode terminal widths', () => {
  const state = new TeamStatus(); state.update([{ name: '中文\x1b\nagent', status: 'running' }]);
  state.input('\x1b[B', '', () => {});
  for (const width of [0, 1, 8, 30, 100]) {
    for (const row of state.render(width, theme)) {
      expect(visibleWidth(row)).toBeLessThanOrEqual(width);
      expect(row.replace(/\x1b\[[0-9;]*m/g, '')).not.toMatch(/[\x00-\x1f]/);
    }
  }
});
