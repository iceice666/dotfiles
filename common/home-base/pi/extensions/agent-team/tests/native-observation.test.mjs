import test from 'node:test';
import assert from 'node:assert/strict';
import { NativeObservation } from '../native-observation.mjs';
import { Team } from '../team.mjs';

const update = (o, type, contentIndex, data = {}) => o.ingest({ type: 'message_update', assistantMessageEvent: { type, contentIndex, ...data } });
const full = (role, content, extra = {}) => ({ role, content, timestamp: 1, ...extra });

test('assembles actual delta-only RPC events and authoritative end with stable ID', () => {
  const o = new NativeObservation();
  o.ingest({ type: 'message_start', message: full('assistant', [], { model: 'test' }) });
  update(o, 'thinking_start', 0); update(o, 'thinking_delta', 0, { delta: 'reason' });
  update(o, 'text_start', 1); update(o, 'text_delta', 1, { delta: 'hello' });
  update(o, 'toolcall_start', 2, { id: 'call', toolName: 'bash' });
  update(o, 'toolcall_delta', 2, { delta: '{"command":"ec' });
  assert.deepEqual(o.snapshot().messages[0].message.content[2].arguments, { command: 'ec' });
  update(o, 'toolcall_delta', 2, { delta: 'ho hi"}' });
  assert.deepEqual(o.snapshot().messages[0].message.content[2].arguments, { command: 'echo hi' });
  const call = { type: 'toolCall', id: 'call', name: 'bash', arguments: { command: 'echo final' } };
  update(o, 'toolcall_end', 2, { toolCall: call });
  const before = o.snapshot().messages[0];
  assert.deepEqual(before.message.content, [{ type: 'thinking', thinking: 'reason' }, { type: 'text', text: 'hello' }, call]);
  assert.equal(before.streaming, true);
  const end = full('assistant', [{ type: 'text', text: 'authoritative' }], { stopReason: 'stop', errorMessage: 'retained', usage: { output: 20 } });
  o.ingest({ type: 'message_end', message: end });
  const after = o.snapshot().messages[0];
  assert.equal(after.id, before.id); assert.equal(after.streaming, false); assert.deepEqual(after.message, end);
});

test('tool execution and toolResult are one ordered record retaining details, args and errors', () => {
  const o = new NativeObservation();
  o.ingest({ type: 'message_start', message: full('user', 'run it') });
  o.ingest({ type: 'message_end', message: full('user', 'run it') });
  o.ingest({ type: 'tool_execution_start', toolCallId: 'c', toolName: 'bash', args: { command: 'false' } });
  o.ingest({ type: 'tool_execution_update', toolCallId: 'c', toolName: 'bash', partialResult: { content: [{ type: 'text', text: 'partial' }], details: { exitCode: null } } });
  assert.equal(o.snapshot().messages[1].streaming, true);
  const result = { content: [{ type: 'text', text: 'final' }], details: { exitCode: 1, fullOutputPath: '/tmp/log', truncation: { truncated: true } } };
  o.ingest({ type: 'tool_execution_end', toolCallId: 'c', toolName: 'bash', result, isError: true });
  const message = full('toolResult', result.content, { toolCallId: 'c', toolName: 'bash', details: result.details, isError: true });
  o.ingest({ type: 'message_start', message }); o.ingest({ type: 'message_end', message });
  assert.equal(o.snapshot().messages.length, 2);
  assert.deepEqual(o.snapshot().messages[1].message, message);
  assert.deepEqual(o.snapshot().messages[1].tool.args, { command: 'false' });
  assert.equal(o.snapshot().messages[1].tool.status, 'completed');
  o.ingest({ type: 'tool_execution_end', toolCallId: 'c', toolName: 'bash', result: { content: [] } });
  assert.deepEqual(o.snapshot().messages[1].message, message);
});

test('snapshots do not alias source events or later updates; unknown events are inert', () => {
  const o = new NativeObservation(), message = full('assistant', []);
  o.ingest({ type: 'message_start', message });
  message.content.push({ type: 'text', text: 'bad' });
  const snapshot = o.snapshot(); snapshot.messages[0].message.content.push({ type: 'text', text: 'also bad' });
  assert.deepEqual(o.snapshot().messages[0].message.content, []);
  const revision = o.revision;
  assert.equal(o.ingest({ type: 'agent_end', messages: [] }), false);
  assert.equal(update(o, 'text_delta', 1e9, { delta: 'bad' }), false);
  assert.equal(o.revision, revision);
});

test('bounds records, huge metadata, images and private argument buffers', () => {
  const o = new NativeObservation(2048, 3);
  for (let i = 0; i < 10; i++) o.ingest({ type: 'message_end', message: full('user', String(i)) });
  assert.equal(o.snapshot().messages.length, 3); assert.equal(o.snapshot().truncated, true);
  assert.deepEqual(o.snapshot().messages.map(e => e.message.content), ['7', '8', '9']);
  o.ingest({ type: 'message_start', message: full('assistant', []) });
  update(o, 'toolcall_start', 0, { id: 'c', toolName: 'write' });
  update(o, 'toolcall_delta', 0, { delta: '{"data":"' + 'x'.repeat(20000) });
  assert.ok(Buffer.byteLength(JSON.stringify(o.messages)) <= 2048);
  o.ingest({ type: 'message_end', message: full('assistant', [{ type: 'image', data: 'x'.repeat(20000), mimeType: 'image/png' }], { metadata: 'x'.repeat(20000) }) });
  assert.ok(Buffer.byteLength(JSON.stringify(o.snapshot())) <= 2048);
});

test('Team observation is passive, lazy, independent of text observation and captures stopped output', () => {
  const team = Object.create(Team.prototype);
  const a = { name: 'worker', status: 'stopped', rpc: { request() { throw new Error('observation must not send RPC'); } } };
  team.agents = new Map([['worker', a]]);
  assert.deepEqual(team.observeNative('worker'), { messages: [], revision: 0, truncated: false });
  assert.throws(() => team.observeNative('unknown'), /Unknown agent/);
  team.event(a, { type: 'message_end', message: full('assistant', [{ type: 'text', text: 'done' }]) });
  assert.equal(team.observeNative('worker').messages[0].message.content[0].text, 'done');
  assert.match(team.observe('worker').text, /done/);
});
