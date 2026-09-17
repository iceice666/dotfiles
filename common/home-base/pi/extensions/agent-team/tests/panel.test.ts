import { expect, test } from 'bun:test';
import { createJiti } from 'jiti';
const jiti = createJiti(import.meta.url, { interopDefault: true, alias: {
  '@earendil-works/pi-tui': import.meta.resolve('@earendil-works/pi-tui'),
  '@earendil-works/pi-coding-agent': import.meta.resolve('@earendil-works/pi-coding-agent'),
} });
const { visibleWidth } = await jiti.import('@earendil-works/pi-tui') as any;
const { initTheme } = await jiti.import('@earendil-works/pi-coding-agent') as any;
initTheme('dark');
const theme = { fg: (_: string, s: string) => s };
const { TranscriptViewer } = await jiti.import('../transcript-viewer.ts') as any;
function fixture(mode = 'regular') {
  let text = Array.from({ length: 60 }, (_, i) => `line ${i}`).join('\n');
  let revision = 1;
  const actions: any[] = [], writes: string[] = [];
  const agents = [{ name: 'alice', status: 'running', activity: 'bash', sessionFile: '/tmp/session' }];
  const source = { list: () => ({ agents }), observeNative: () => ({ messages: [{ id: '1', message: { role: 'user', content: text }, streaming: false }], truncated: false, revision }) };
  const tui = { mode, terminal: { rows: 24, write: (s: string) => writes.push(s) }, requestRender() {} };
  const viewer = new TranscriptViewer(source, tui, theme, (action: any) => actions.push(action), 'alice');
  return { viewer, tui, agents, actions, writes, update: () => { text += '\nnewest'; revision++; } };
}
test('fullscreen viewer follows, scrolls, and detaches locally', () => {
  const s = fixture();
  expect(s.viewer.render(80)).toHaveLength(24);
  expect(s.viewer.render(80).join('\n')).toContain('line 59');
  s.viewer.handleInput('\x1b[H');
  expect(s.viewer.render(80).join('\n')).toContain('line 0');
  s.update(); expect(s.viewer.render(80).join('\n')).not.toContain('newest');
  s.viewer.handleInput('f'); expect(s.viewer.render(80).join('\n')).toContain('newest');
  s.viewer.handleInput('arbitrary text to steer'); s.viewer.handleInput('\r');
  expect(s.agents[0].status).toBe('running');
  s.viewer.handleInput('\x1b'); expect(s.actions.at(-1)).toBe('close');
  s.viewer.handleInput('q'); expect(s.actions.at(-1)).toBe('close');
  s.viewer.dispose();
});
test('stopped worker transcript remains readable without reviving the worker', () => {
  const s = fixture();
  s.agents[0].status = 'stopped';
  expect(s.viewer.render(80).join('\n')).toContain('stopped');
  expect(s.viewer.render(80).join('\n')).toContain('line 59');
  s.viewer.handleInput('\x1b');
  expect(s.actions).toEqual(['close']);
  expect(s.agents[0].status).toBe('stopped');
  s.viewer.dispose();
});

test('regular SGR wheel and fullscreen normalized wheel scroll; mouse mode restored', () => {
  for (const mode of ['regular', 'fullscreen']) {
    const s = fixture(mode);
    s.viewer.render(80);
    if (mode === 'regular') s.viewer.handleInput('\x1b[<64;20;10M');
    else expect(s.viewer.handleMouse({ type: 'wheel', wheelDelta: -3 })).toEqual({ handled: true, render: true });
    expect(s.viewer.render(80).join('\n')).toContain('SCROLL');
    expect(s.viewer.render(80).join('\n')).not.toContain('line 59');
    s.viewer.handleInput('\x1b[6~');
    expect(s.viewer.render(80).join('\n')).toContain('line 59');
    s.viewer.dispose(); s.viewer.dispose();
    expect(s.writes).toHaveLength(mode === 'regular' ? 2 : 0);
    if (mode === 'regular') expect(s.writes[1]).toContain('?1000l');
  }
});
test('transcript respects widths and resize', () => {
  const s = fixture();
  for (const width of [1, 2, 10, 40, 120]) {
    for (const component of [s.viewer]) for (const line of component.render(width)) expect(visibleWidth(line)).toBeLessThanOrEqual(width);
  }
  s.tui.terminal.rows = 40; expect(s.viewer.render(80)).toHaveLength(40);
  s.viewer.dispose();
});

test('native transcript uses Pi Markdown/thinking/tool renderers with recorded diffs', async () => {
  const { NativeTranscript } = await jiti.import('../native-transcript.ts') as any;
  const { stripVTControlCharacters } = await import('node:util');
  const view = new NativeTranscript({ requestRender() {} }, '/does-not-exist');
  const snapshot = { revision: 1, truncated: false, messages: [
    { id: 'a', streaming: false, message: { role: 'assistant', content: [
      { type: 'thinking', thinking: 'Think about the fix' },
      { type: 'text', text: '**Native bold** and `code`' },
      { type: 'toolCall', id: 't', name: 'edit', arguments: { path: 'not-on-disk.ts', edits: [{ oldText: 'old', newText: 'new' }] } },
    ], stopReason: 'toolUse' } },
    { id: 't', streaming: false, tool: { args: { path: 'not-on-disk.ts', edits: [{ oldText: 'old', newText: 'new' }] }, status: 'completed' },
      message: { role: 'toolResult', toolCallId: 't', toolName: 'edit', content: [{ type: 'text', text: 'Successfully edited' }], details: { diff: '-1 old\n+1 new', firstChangedLine: 1 }, isError: false } },
  ] };
  view.update(snapshot);
  const ansi = view.render(80).join('\n');
  const text = stripVTControlCharacters(ansi);
  expect(ansi).toContain('\x1b[');
  expect(text).toContain('Native bold'); expect(text).not.toContain('**Native bold**');
  expect(text).toContain('Think about the fix');
  expect(text).toContain('not-on-disk.ts'); expect(text).toContain('old'); expect(text).toContain('new');
  expect(text).not.toContain('[Tool call:');
  view.toggleThinking();
  expect(stripVTControlCharacters(view.render(80).join('\n'))).not.toContain('Think about the fix');
  for (const width of [4, 10, 40]) for (const line of view.render(width)) expect(visibleWidth(line)).toBeLessThanOrEqual(width);
});

test('native unknown tool output expands without execution and handles partial updates', async () => {
  const { NativeTranscript } = await jiti.import('../native-transcript.ts') as any;
  const { stripVTControlCharacters } = await import('node:util');
  const view = new NativeTranscript({ requestRender() {} }, '/tmp');
  const message = { role: 'toolResult', toolCallId: 'x', toolName: 'custom_tool', content: [{ type: 'text', text: Array.from({ length: 40 }, (_, i) => `output-${i}`).join('\n') }], isError: false };
  view.update({ revision: 1, truncated: false, messages: [{ id: 'x', message, streaming: true, tool: { args: {}, status: 'running' } }] });
  expect(stripVTControlCharacters(view.render(80).join('\n'))).not.toContain('output-39');
  view.toggleExpanded();
  expect(stripVTControlCharacters(view.render(80).join('\n'))).toContain('output-39');
  view.update({ revision: 2, truncated: true, messages: [{ id: 'x', message: { ...message, content: [{ type: 'text', text: 'final result' }] }, streaming: false }] });
  const output = stripVTControlCharacters(view.render(80).join('\n'));
  expect(output).toContain('final result'); expect(output).not.toContain('output-39'); expect(output).toContain('truncated');
});


test('native images become placeholders and result-only records preserve call arguments', async () => {
  const { NativeTranscript } = await jiti.import('../native-transcript.ts') as any;
  const { stripVTControlCharacters } = await import('node:util');
  const view = new NativeTranscript({ requestRender() {} }, '/tmp');
  view.update({ revision: 1, truncated: false, messages: [
    { id: 'a', streaming: false, message: { role: 'assistant', stopReason: 'toolUse', content: [{ type: 'toolCall', id: 'r', name: 'read', arguments: { path: 'keep-this-path.ts' } }] } },
    { id: 'r', streaming: false, tool: { args: {}, status: 'completed' }, message: { role: 'toolResult', toolCallId: 'r', toolName: 'read', content: [{ type: 'image', mimeType: 'image/jpeg', data: 'invalid-data-must-not-be-decoded' }], isError: false } },
  ] });
  view.toggleExpanded(); // Native read cards hide successful output until expanded.
  const text = stripVTControlCharacters(view.render(80).join('\n'));
  expect(text).toContain('keep-this-path.ts'); expect(text).toContain('[Image]');
  expect(text).not.toContain('invalid-data');
});
