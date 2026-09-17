import test from 'node:test';
import assert from 'node:assert/strict';
import { Observation, safeText } from '../observation.mjs';
import { Team } from '../team.mjs';

const update = (o, type, fields = {}) => o.ingest({ type: 'message_update', assistantMessageEvent: { type, contentIndex: 0, ...fields } });
test('delta-only text, thinking and tool arguments stream live; authoritative end replaces', () => {
  const o = new Observation();
  o.ingest({ type: 'message_start', message: { role: 'user', content: 'task' } });
  o.ingest({ type: 'message_end', message: { role: 'user', content: 'task' } });
  o.ingest({ type: 'message_start', message: { role: 'assistant', content: [] } });
  update(o, 'text_start'); update(o, 'text_delta', { delta: 'Hello' }); update(o, 'text_delta', { delta: ' world' });
  assert.match(o.snapshot().text, /Hello world/);
  update(o, 'text_end', { content: 'Hello world' });
  update(o, 'thinking_start', { contentIndex: 1 });
  update(o, 'thinking_delta', { contentIndex: 1, delta: 'reason' });
  update(o, 'toolcall_start', { contentIndex: 2, toolName: 'bash', id: 'call' });
  update(o, 'toolcall_delta', { contentIndex: 2, delta: '{"command":"ls"}' });
  assert.match(o.snapshot().text, /Thinking.*\nreason/);
  assert.match(o.snapshot().text, /Tool call: bash.*\n\{"command":"ls"\}/);
  o.ingest({ type: 'message_end', message: { role: 'assistant', content: [{ type: 'text', text: 'Hello world!' }] } });
  assert.equal(o.snapshot().text, '[user]\ntask\n\n[assistant]\nHello world!');
});
test('legacy snapshots replace, execution updates and final tool messages deduplicate', () => {
  const o = new Observation();
  for (const text of ['one', 'one two']) o.ingest({ type: 'message_update', message: { role: 'assistant', content: [{ type: 'text', text }] } });
  assert.equal(o.snapshot().text, '[assistant]\none two');
  const common = { toolCallId: 'call', toolName: 'bash' };
  o.ingest({ type: 'tool_execution_start', ...common });
  for (const text of ['out', 'output']) o.ingest({ type: 'tool_execution_update', ...common, partialResult: { content: [{ type: 'text', text }] } });
  assert.match(o.snapshot().text, /\noutput$/);
  o.ingest({ type: 'tool_execution_end', ...common, result: { content: [{ type: 'text', text: 'output done' }] } });
  for (const type of ['message_start', 'message_end']) o.ingest({ type, message: { role: 'toolResult', ...common, content: [{ type: 'text', text: 'output done' }] } });
  assert.equal(o.snapshot().text.split('output done').length, 2);
  assert.equal(o.snapshot().text.split('[Tool result: bash]').length, 2);
});
test('transcript bounds UTF-8 data and entry bookkeeping with explicit truncation', () => {
  const o = new Observation(1024);
  for (let i = 0; i < 2000; i++) o.ingest({ type: 'message_end', message: { role: 'user', content: `old ${i}` } });
  o.ingest({ type: 'message_start', message: { role: 'assistant', content: [] } });
  for (let i = 0; i < 100; i++) update(o, 'text_delta', { delta: '中'.repeat(500) });
  assert.ok(Buffer.byteLength(o.snapshot().text) <= 1024);
  assert.match(o.snapshot().text, /Observation truncated; full history is in the agent sessionFile/);
  assert.doesNotMatch(o.snapshot().text, /\ufffd/);
  assert.ok(o.entries.length < 100);
  assert.ok(Buffer.byteLength(JSON.stringify(o.entries.map(e => [...e.parts.values()]))) < 1100);
});
test('safeText prevents terminal controls and bidi overrides', () => {
  assert.equal(safeText('a\x1b[2J\x00\x07\x9b\r\nb\u202ec\t'), 'a\nbc\t');
});
test('Team observation is passive, repeatable, isolated, and survives stopping', () => {
  const team = Object.create(Team.prototype);
  let commands = 0;
  const o = new Observation();
  o.ingest({ type: 'message_end', message: { role: 'user', content: 'private task' } });
  const agent = { name: 'worker', status: 'stopped', sessionFile: '/sessions/full.jsonl', task: 'task', pid: 12, startedAt: 'start', lastActivity: 'last', activity: 'stopped', observation: o, rpc: { request() { commands++; } } };
  team.agents = new Map([['worker', agent]]);
  const before = o.revision;
  const snapshot = team.observe('worker'); snapshot.text = 'mutated';
  assert.equal(team.observe('worker').text, '[user]\nprivate task');
  assert.equal(o.revision, before); assert.equal(commands, 0);
  assert.equal(team.list().agents[0].sessionFile, '/sessions/full.jsonl');
  assert.equal(team.list().agents[0].pid, 12);
  assert.equal(team.list().agents[0].task, 'task');
  assert.throws(() => team.observe('missing'), /Unknown agent/);
});
