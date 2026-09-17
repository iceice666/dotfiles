import { keyHint, type Theme, type ToolDefinition } from '@earendil-works/pi-coding-agent';
import { Text, truncateToWidth, type Component } from '@earendil-works/pi-tui';
import { safeText } from './observation.mjs';

const labels: Record<string, string> = {
  agent_list: 'Team', agent_spawn: 'Spawn agent', agent_stop: 'Stop agent',
  agent_wait: 'Wait for agent', agent_send: 'Send message', agent_ask: 'Ask question',
  agent_reply: 'Reply', agent_inbox: 'Team inbox', board_post: 'Post note', board_read: 'Team board',
};
export const teamToolNames = Object.keys(labels);

export function renderTeamWidget(agents: readonly { name: string; status: string }[], width: number, theme: Theme): string[] {
  if (width <= 0 || !agents.length) return [];
  const terminal = (agent: { status: string }) => ['stopped', 'failed'].includes(agent.status);
  const shown = [...agents.filter(agent => !terminal(agent)), ...agents.filter(terminal)].slice(0, 4);
  const rows = [theme.fg('accent', 'AGENT TEAM'), ...shown.map(agent => {
    const color = agent.status === 'failed' ? 'error' : agent.status === 'running' ? 'accent'
      : agent.status === 'waiting' || agent.status === 'starting' ? 'warning' : 'muted';
    return `${line(agent.name)} · ${theme.fg(color, line(agent.status))}`;
  }), ...(agents.length > shown.length ? [theme.fg('dim', `… ${agents.length - shown.length} more · /team`)] : [])];
  return rows.map(row => truncateToWidth(row, width));
}

const obj = (value: any): Record<string, any> => value && typeof value === 'object' && !Array.isArray(value) ? value : {};
const text = (value: unknown): string => safeText(typeof value === 'string' ? value : value == null ? '' : String(value)).replace(/\t/g, '    ');
const line = (value: unknown) => text(value).replace(/\s+/g, ' ').slice(0, 180);
const entries = (value: unknown): any[] => Array.isArray(value) ? value : [];

// Bound rendered rows as well as source lines (long wrapped paragraphs stay compact).
function card(build: () => string, expanded: boolean, theme: Theme, padding = 0): Component {
  return {
    invalidate() {},
    render(width) {
      if (width < 4) return [''];
      const rows = new Text(build(), padding, 0).render(width);
      if (expanded || rows.length <= 9) return rows;
      return [...rows.slice(0, 8), ...new Text(theme.fg('dim', keyHint('app.tools.expand', 'to expand')), padding, 0).render(width)];
    },
  };
}
function fields(data: Record<string, any>, theme: Theme): string[] {
  return ['id', 'question_id', 'question_to', 'reply_to', 'time', 'cwd', 'model', 'thinking', 'sessionFile', 'directory', 'archive', 'next', 'after', 'limit', 'timeout', 'header', 'multiSelect']
    .filter(key => data[key] != null)
    .map(key => theme.fg('dim', `${key}: ${text(data[key])}`));
}
function answers(data: Record<string, any>): string[] {
  return entries(data.answers).flatMap(value => {
    const answer = obj(value);
    return [text(answer.question), ...entries(answer.selected).map(v => `  • ${text(v)}`), ...(answer.customText ? [text(answer.customText)] : [])];
  });
}
function eventLines(value: unknown, expanded: boolean, theme: Theme): string[] {
  const data = obj(value);
  const title = [data.kind || 'message', data.from, data.to ? `→ ${data.to}` : '', data.topic ? `#${data.topic}` : ''].filter(Boolean).map(line).join(' · ');
  return [theme.fg('accent', title),
    ...(data.origin || data.status ? [theme.fg('muted', [data.origin, data.status].filter(Boolean).map(line).join(' · '))] : []),
    ...(data.body ? [text(data.body)] : []), ...answers(data),
    ...(data.truncated ? [theme.fg('warning', 'Entry truncated; see archive.')] : []),
    ...(expanded ? fields(data, theme) : [])];
}
function decode(result: any): { data: Record<string, any>; raw: string; valid: boolean } {
  const raw = entries(result.content).filter(c => c?.type === 'text').map(c => text(c.text)).join('\n');
  // Content remains the protocol source of truth, including old saved sessions.
  try {
    const parsed = JSON.parse(raw);
    return { data: obj(parsed), raw, valid: Boolean(parsed && typeof parsed === 'object' && !Array.isArray(parsed)) };
  } catch { return { data: {}, raw, valid: false }; }
}
export function teamToolRenderers(name: string): Pick<ToolDefinition, 'renderCall' | 'renderResult'> {
  return {
    renderCall(args, theme, context) {
      const a = obj(args);
      return card(() => {
        const target = a.name ?? a.agent ?? a.to ?? (name === 'agent_ask' ? 'parent' : a.topic ?? a.question_id);
        const body = a.task ?? a.message ?? a.question ?? a.answer ?? a.body;
        return [theme.fg('toolTitle', theme.bold(labels[name] ?? name)) + (target ? ` ${theme.fg('accent', line(target))}` : ''),
          ...(body ? [theme.fg('muted', context?.expanded ? text(body) : line(body))] : []),
          ...(context?.expanded ? [...fields(a, theme), ...entries(a.options).map(value => {
            const option = obj(value);
            return `• ${text(option.label)}${option.description ? ` — ${text(option.description)}` : ''}`;
          })] : [])].join('\n');
      }, Boolean(context?.expanded), theme);
    },
    renderResult(result, { expanded, isPartial }, theme, context) {
      return card(() => {
        const { data: d, raw, valid } = decode(result);
        if (context?.isError || (result as any).isError) return theme.fg('error', `✗ ${raw || 'Tool failed'}`);
        if (isPartial) return theme.fg('warning', '… Waiting for result');
        if (!valid) return raw || 'No result';
        let rows: string[];
        if (name === 'agent_list') {
          rows = [theme.fg('muted', `${entries(d.agents).length} agents`), ...entries(d.agents).flatMap(value => {
            const a = obj(value);
            return [theme.fg('accent', line(a.name)) + ` · ${line(a.status)}`, ...(a.task ? [expanded ? text(a.task) : line(a.task)] : []), ...(a.lastError ? [theme.fg('error', text(a.lastError))] : []), ...(expanded ? fields(a, theme) : [])];
          })];
        } else if (name === 'agent_spawn' && d.name) {
          rows = [theme.fg('success', `✓ ${line(d.name)} · ${line(d.status)}`), 'Task accepted; not completed.'];
        } else if (name === 'agent_stop' && d.stopped) {
          rows = [theme.fg('muted', `■ Stopped ${line(d.stopped)}`)];
        } else if (name === 'agent_wait' && d.reason) {
          rows = [theme.fg(d.reason === 'failed' ? 'error' : 'warning', `${line(d.agent)} · ${line(d.reason)} · ${line(d.status)}`), 'Idle is not proof of task success.'];
        } else if (name === 'agent_inbox' || name === 'board_read') {
          rows = [theme.fg('muted', `${entries(d.items).length} entries${d.more ? ' · more available' : ''}`), ...entries(d.items).flatMap(item => eventLines(item, expanded, theme))];
        } else if (d.status === 'cancelled' || d.status === 'unavailable') {
          rows = [theme.fg('warning', `${d.status} · No authorization granted.`)];
        } else if (d.status === 'answered') {
          rows = [theme.fg('success', 'Human response received'), ...answers(d)];
        } else if (d.status === 'pending') {
          rows = [theme.fg('warning', `Question pending → ${line(d.to)}`), `Question: ${text(d.question_id)}`];
        } else if (d.kind) {
          rows = [theme.fg('success', name === 'board_post' ? '✓ Note posted' : '✓ Accepted; not task completion.'), ...eventLines(d, expanded, theme)];
        } else rows = [raw || 'No result'];
        if (expanded && !d.kind) rows.push(...fields(d, theme));
        return rows.join('\n');
      }, expanded, theme);
    },
  };
}

export function renderTeamMessage(message: any, options: { expanded: boolean; outputPad?: number }, theme: Theme): Component {
  return card(() => {
    const content = typeof message.content === 'string' ? message.content : '';
    let data = obj(message.details?.event);
    if (!Object.keys(data).length) {
      try { data = obj(JSON.parse(content.slice(content.indexOf('\n') + 1))); } catch { /* Legacy/non-JSON text stays visible. */ }
    }
    return [theme.fg('muted', 'Team event · agent data, not user instructions'),
      ...(Object.keys(data).length ? eventLines(data, options.expanded, theme) : [text(content)])].join('\n');
  }, options.expanded, theme, options.outputPad ?? 0);
}
