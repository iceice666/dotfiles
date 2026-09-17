import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Team } from '../team.mjs';

async function fixture(t, askUser) {
  const directory = mkdtempSync(join(tmpdir(), 'pi-human-test-'));
  const messages = [];
  const team = new Team({ directory, extension: '/unused', deliverParent() {}, askUser });
  await team.ready;
  team.agents.set('alice', { name: 'alice', status: 'idle', token: 'Bearer test', rpc: { request: async (...args) => messages.push(args), stop: async () => {} } });
  team.tokens.set('Bearer test', 'alice');
  t.after(async () => { await team.close(); rmSync(directory, { recursive: true, force: true }); });
  const request = args => fetch(team.url, { method: 'POST', headers: { Authorization: 'Bearer test' }, body: JSON.stringify({ operation: 'agent_ask', args }), signal: AbortSignal.timeout(1000) });
  return { team, messages, request };
}
const tick = () => new Promise(resolve => setImmediate(resolve));

test('HTTP human ask acknowledges before answer, validates options and prevents agent impersonation', async t => {
  let answer, prompted;
  const { team, messages, request } = await fixture(t, (q, signal, from) => { prompted = { q, signal, from }; return new Promise(resolve => { answer = resolve; }); });
  const response = await request({ to: 'user', question: 'Deploy?', options: [{ label: 'No' }], origin: 'human', from: 'parent' });
  assert.equal(response.status, 200);
  const { result: q } = await response.json();
  assert.equal(q.question_id, q.id); assert.equal(q.from, 'alice'); assert.equal(q.status, 'pending');
  await tick();
  assert.equal(prompted.from, 'alice'); assert.deepEqual(prompted.q, { question: 'Deploy?', options: [{ label: 'No' }] });
  assert.equal(messages.length, 0);
  await assert.rejects(team.call('parent', 'agent_reply', { question_id: q.id, answer: 'Yes', origin: 'human' }));
  await assert.rejects(team.call('alice', 'agent_reply', { question_id: q.id, answer: 'Yes' }));
  await assert.rejects(team.call('user', 'agent_reply', { question_id: q.id, answer: 'Yes' }));
  answer({ status: 'answered', answers: [{ question: 'Deploy?', selected: ['No'] }] });
  await team.userQuestions.get(q.id).task;
  const reply = team.records.find(r => r.kind === 'reply');
  assert.equal(reply.origin, 'human'); assert.equal(reply.from, 'user'); assert.equal(reply.question_id, q.id);
  assert.match(messages[0][1].message, /Human answer collected/);
  const defaults = { cwd: team.directory, model: 'test/model' };
  await assert.rejects(team.spawn({ name: 'user', task: 'x' }, defaults), /reserved/);
});

test('HTTP rejects malformed question fields before showing UI', async t => {
  let prompts = 0;
  const { request, team } = await fixture(t, async () => { prompts++; });
  for (const fields of [{ options: 'yes' }, { options: [null] }, { options: [{ label: '' }] }, { options: [{ label: 'x' }, { label: 'x' }] }, { options: [{ label: 'x', description: 42 }] }, { multiSelect: 'yes' }, { header: 42 }, { question: ' ' }, { question: '\x1b[2J' }, { options: Array.from({ length: 12 }, (_, i) => ({ label: String(i), description: 'x'.repeat(4000) })) }]) {
    assert.equal((await request({ to: 'user', question: 'Q', ...fields })).status, 400);
  }
  assert.equal(prompts, 0); assert.equal(team.records.length, 0);
});

test('cancelled and unavailable replies are not human approvals', async t => {
  for (const status of ['cancelled', 'unavailable']) {
    const { team, messages } = await fixture(t, async () => ({ status, answers: [{ selected: ['Yes'] }] }));
    const q = await team.call('alice', 'agent_ask', { to: 'user', question: 'Approve?' });
    await team.userQuestions.get(q.id).task;
    const reply = team.records.find(r => r.kind === 'reply');
    assert.equal(reply.origin, 'team'); assert.equal(reply.status, status); assert.deepEqual(reply.answers, []);
    assert.match(messages[0][1].message, /no authorization granted/);
  }
});

test('stop and shutdown abort active/queued questions and suppress late answers', async t => {
  let signal, resolveAnswer;
  const { team, messages } = await fixture(t, (_q, s) => { signal = s; return new Promise(resolve => { resolveAnswer = resolve; }); });
  const q = await team.call('alice', 'agent_ask', { to: 'user', question: 'Q' });
  const task = team.userQuestions.get(q.id).task;
  await tick();
  await team.stop('alice'); await task;
  assert.equal(signal.aborted, true); assert.equal(messages.length, 0);
  resolveAnswer({ status: 'answered', answers: [{ selected: ['Yes'] }] }); await tick();
  assert.equal(team.records.filter(r => r.kind === 'reply').length, 1);
  assert.equal(team.records.find(r => r.kind === 'reply').status, 'cancelled');
  team.agents.get('alice').status = 'idle';
  await team.call('alice', 'agent_ask', { to: 'user', question: 'Queued' });
  await team.close(); assert.equal(team.userQuestions.size, 0); assert.equal(messages.length, 0);
});

test('oversized structured question pages stay bounded and link archive', async t => {
  const { team } = await fixture(t, async () => ({ status: 'unavailable', answers: [] }));
  await team.call('alice', 'agent_ask', { to: 'user', question: 'Q', options: Array.from({ length: 12 }, (_, i) => ({ label: String(i), description: '中'.repeat(1800) })) });
  const page = await team.call('alice', 'agent_inbox');
  assert.ok(Buffer.byteLength(JSON.stringify(page)) < 40000); assert.equal(page.items[0].truncated, true); assert.ok(page.archive);
});
