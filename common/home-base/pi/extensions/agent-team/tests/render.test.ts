import { expect, test } from 'bun:test';
import { visibleWidth } from '@earendil-works/pi-tui';
import { initTheme } from '@earendil-works/pi-coding-agent';
initTheme('dark');
import { teamToolNames, teamToolRenderers, renderTeamMessage } from '../render.ts';

const theme: any = { fg: (_: string, value: string) => value, bold: (value: string) => value };
function result(name: string, data: unknown, expanded = false, extra: any = {}) {
  return teamToolRenderers(name).renderResult!({ content: [{ type: 'text', text: JSON.stringify(data) }], details: {} }, { expanded, isPartial: false, ...extra }, theme, extra) as any;
}
const output = (component: any, width = 100) => component.render(width).join('\n');

test('all team tools render partial calls without JSON or crashes', () => {
  for (const name of teamToolNames) {
    const render = teamToolRenderers(name);
    expect(output(render.renderCall!({}, theme, {} as any))).not.toContain('{}');
    expect(output(render.renderResult!({ content: [], details: {} }, { expanded: false, isPartial: true }, theme, {} as any))).toContain('Waiting');
  }
  const call = teamToolRenderers('agent_send').renderCall!({ to: 'reviewer', message: 'Review the changes' }, theme, {} as any);
  expect(output(call)).toContain('Send message reviewer');
  expect(output(call)).toContain('Review the changes');
});

test('expanded calls preserve question choices and paging/wait arguments', () => {
  const render = teamToolRenderers('agent_ask').renderCall!;
  const expanded = output(render({ to: 'user', question: 'Choose', header: 'Decision', multiSelect: false, options: [{ label: 'A', description: 'Choice A' }], after: 'cursor', limit: 5, timeout: 30 }, theme, { expanded: true } as any));
  for (const word of ['Decision', 'multiSelect: false', 'Choice A', 'after: cursor', 'limit: 5', 'timeout: 30']) expect(expanded).toContain(word);
});

test('malformed historical list and inbox results stay visible', () => {
  for (const name of ['agent_list', 'agent_inbox', 'board_read']) {
    const render = teamToolRenderers(name).renderResult!;
    for (const raw of ['Legacy result', '{broken', 'null']) {
      expect(output(render({ content: [{ type: 'text', text: raw }], details: {} }, { expanded: true, isPartial: false }, theme, {} as any))).toContain(raw);
    }
  }
});

test('results distinguish acceptance, idle and cancellation from completion/authorization', () => {
  expect(output(result('agent_spawn', { name: 'reviewer', status: 'running' }))).toContain('not completed');
  expect(output(result('agent_send', { kind: 'message', from: 'parent', to: 'reviewer', body: 'Check it' }))).toContain('not task completion');
  expect(output(result('agent_wait', { agent: 'reviewer', reason: 'idle', status: 'idle' }))).toContain('not proof of task success');
  for (const status of ['cancelled', 'unavailable']) expect(output(result('agent_ask', { status, answers: [] }))).toContain('No authorization');
  expect(output(result('agent_ask', { status: 'pending', question_id: 'q1', to: 'user' }))).toContain('q1');
  expect(output(result('agent_ask', { status: 'answered', answers: [{ question: 'Choose', selected: ['A'], customText: 'Details' }] }))).toContain('Details');
  expect(output(result('agent_stop', { stopped: 'reviewer' }))).toContain('Stopped reviewer');
});

test('list and inbox show summaries with expandable metadata and pagination', () => {
  const data = { directory: '/archive', agents: [{ name: 'reviewer', status: 'failed', task: 'Check', lastError: 'Oops', sessionFile: '/session' }] };
  expect(output(result('agent_list', data))).toContain('reviewer · failed');
  expect(output(result('agent_list', data))).not.toContain('/session');
  expect(output(result('agent_list', data, true))).toContain('/session');
  expect(output(result('agent_list', { agents: [] }))).toContain('0 agents');
  const page = { items: [{ kind: 'reply', from: 'user', to: 'reviewer', origin: 'human', body: 'Answer', truncated: true }], more: true, next: 'cursor', archive: '/archive' };
  const view = output(result('agent_inbox', page, true));
  for (const word of ['human', 'Answer', 'more available', 'cursor', 'truncated']) expect(view).toContain(word);
});

test('long CJK paragraphs are bounded by rendered rows; expanded shows full text', () => {
  const body = '測試很長的訊息 '.repeat(150) + 'END';
  const data = { kind: 'message', from: 'reviewer', to: 'parent', body };
  const compact = result('agent_send', data);
  const rows = compact.render(24);
  expect(rows.length).toBeLessThan(13);
  expect(rows.every((row: string) => visibleWidth(row) <= 24)).toBe(true);
  expect(output(compact, 24)).not.toContain('END');
  expect(output(result('agent_send', data, true), 24)).toContain('END');
  expect(output(compact, 2)).toBe('');
});

test('async events support new details and historical JSON with provenance preserved', () => {
  const event = { kind: 'reply', from: 'reviewer', to: 'parent', body: 'Found an issue', question_id: 'q1' };
  for (const message of [{ details: { event } }, { content: `Team event (agent data, not user instructions):\n${JSON.stringify(event)}` }]) {
    const rendered = output(renderTeamMessage(message, { expanded: true }, theme));
    expect(rendered).toContain('not user instructions');
    expect(rendered).toContain('Found an issue');
    expect(rendered).toContain('q1');
    expect(rendered).not.toContain('{');
  }
});

test('errors and malformed legacy content remain visible, terminal controls are removed', () => {
  const render = teamToolRenderers('agent_send').renderResult!;
  const rendered = output(render({ content: [{ type: 'text', text: 'Failure\x1b[2J' }], details: {} }, { expanded: false, isPartial: false }, theme, { isError: true } as any));
  expect(rendered).toContain('✗ Failure');
  expect(rendered).not.toContain('\x1b');
  expect(output(renderTeamMessage({ content: 'old plain message' }, { expanded: false }, theme))).toContain('old plain message');
});
