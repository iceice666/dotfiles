import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Team, remoteWait } from '../team.mjs';

async function fixture(t) {
  const directory = mkdtempSync(join(tmpdir(), 'pi-wait-'));
  const team = new Team({ directory, extension: '/unused', deliverParent() {} });
  await team.ready;
  t.after(async () => { await team.close(); rmSync(directory, { recursive: true, force: true }); });
  for (const name of ['alice', 'bob', 'carol']) {
    team.agents.set(name, { name, status: 'running', token: `Bearer ${name}`, rpc: { request: async () => {}, stop: async () => {} } });
    team.tokens.set(`Bearer ${name}`, name);
  }
  return team;
}

test('wait resolves on settled, not final text, agent_end or retry; already idle returns immediately', async t => {
  const team = await fixture(t), a = team.agents.get('alice');
  const pending = team.call('parent', 'agent_wait', { agent: 'alice' });
  team.event(a, { type: 'message_end', message: { role: 'assistant', content: [{ type: 'text', text: 'done' }], stopReason: 'stop' } });
  team.event(a, { type: 'agent_end', willRetry: true });
  assert.equal(team.waiters.size, 1);
  team.event(a, { type: 'agent_settled' });
  assert.equal((await pending).reason, 'idle');
  assert.equal((await team.call('parent', 'agent_wait', { agent: 'alice' })).reason, 'idle');
  assert.equal(team.waiters.size, 0);
});

test('send marks idle worker running before RPC acceptance and restores on failure', async t => {
  const team = await fixture(t), a = team.agents.get('alice');
  team.change(a, 'idle');
  await team.call('parent', 'agent_send', { to: 'alice', message: 'work' });
  assert.equal(a.status, 'running');
  const pending = team.call('parent', 'agent_wait', { agent: 'alice' });
  assert.equal(team.waiters.size, 1);
  team.event(a, { type: 'agent_settled' });
  await pending;
  a.rpc.request = async () => { throw new Error('no'); };
  await assert.rejects(team.send('parent', 'alice', 'work'), /no/);
  assert.equal(a.status, 'idle');
});

test('failed delivery cannot roll back a newer accepted task or worker event', async t => {
  const team = await fixture(t), a = team.agents.get('alice');
  for (const newer of ['delivery', 'event']) {
    team.change(a, 'idle');
    let reject;
    a.rpc.request = () => new Promise((_resolve, no) => { reject = no; });
    const first = assert.rejects(team.send('parent', 'alice', 'first'), /rejected/);
    if (newer === 'delivery') {
      a.rpc.request = async () => {};
      await team.send('parent', 'alice', 'second');
    } else team.event(a, { type: 'agent_start' });
    reject(new Error('rejected'));
    await first;
    assert.equal(a.status, 'running');
    const pending = team.call('parent', 'agent_wait', { agent: 'alice' });
    assert.equal(team.waiters.size, 1);
    team.event(a, { type: 'agent_settled' });
    assert.equal((await pending).reason, 'idle');
  }
});

test('timeout and cancellation clean waiters without stopping workers', async t => {
  const team = await fixture(t);
  assert.equal((await team.call('parent', 'agent_wait', { agent: 'alice', timeout: 0.01 })).reason, 'timeout');
  const controller = new AbortController();
  const pending = team.call('parent', 'agent_wait', { agent: 'alice' }, controller.signal);
  controller.abort();
  assert.equal((await pending).reason, 'cancelled');
  assert.equal((await team.call('parent', 'agent_wait', { agent: 'alice' }, controller.signal)).reason, 'cancelled');
  assert.equal(team.waiters.size, 0);
  assert.equal(team.agents.get('alice').status, 'running');
});

test('validation and multi-hop wait cycles are rejected', async t => {
  const team = await fixture(t);
  for (const agent of ['parent', 'user', 'missing', '', 'alice']) await assert.rejects(team.call('alice', 'agent_wait', { agent }));
  for (const timeout of [0, -1, NaN, Infinity, 86401, '5']) await assert.rejects(team.call('parent', 'agent_wait', { agent: 'alice', timeout }));
  const ab = team.call('alice', 'agent_wait', { agent: 'bob' });
  const bc = team.call('bob', 'agent_wait', { agent: 'carol' });
  await assert.rejects(team.call('carol', 'agent_wait', { agent: 'alice' }), /cycle/);
  await team.close();
  assert.equal((await ab).reason, 'closed');
  assert.equal((await bc).reason, 'closed');
  assert.equal(team.waiters.size, 0);
});

test('questions interrupt waits promptly, including another worker asking caller', async t => {
  const team = await fixture(t);
  let pending = team.call('parent', 'agent_wait', { agent: 'alice' });
  const question = await team.call('bob', 'agent_ask', { question: 'Need guidance' });
  assert.equal((await pending).question_id, question.id);
  await team.call('parent', 'agent_reply', { question_id: question.id, answer: 'Proceed' });
  pending = team.call('bob', 'agent_wait', { agent: 'alice' });
  const human = await team.call('alice', 'agent_ask', { to: 'user', question: 'Approve?' });
  assert.equal((await pending).question_id, human.id);
  assert.equal(team.waiters.size, 0);
});

test('abandoned questions from stopped workers do not interrupt unrelated waits', async t => {
  const team = await fixture(t);
  await team.call('bob', 'agent_ask', { question: 'Need guidance' });
  await team.stop('bob');
  const pending = team.call('parent', 'agent_wait', { agent: 'alice' });
  assert.equal(team.waiters.size, 1);
  team.event(team.agents.get('alice'), { type: 'agent_settled' });
  assert.equal((await pending).reason, 'idle');
});

test('stop, failure, caller stop and disposal all release waits', async t => {
  const team = await fixture(t);
  let pending = team.call('parent', 'agent_wait', { agent: 'alice' });
  await team.stop('alice');
  assert.equal((await pending).reason, 'stopped');
  pending = team.call('parent', 'agent_wait', { agent: 'bob' });
  team.event(team.agents.get('bob'), { type: 'team_exit', code: 1, stderr: '' });
  assert.equal((await pending).reason, 'failed');
  team.change(team.agents.get('alice'), 'running');
  pending = team.call('alice', 'agent_wait', { agent: 'carol' });
  await team.stop('alice');
  assert.equal((await pending).reason, 'caller_stopped');
});

test('child HTTP wait authenticates, returns settled and releases on disconnect', async t => {
  const team = await fixture(t);
  assert.equal((await fetch(team.url, { method: 'POST', body: JSON.stringify({ operation: 'agent_wait', args: { agent: 'alice' } }) })).status, 401);
  let entered, observed;
  let started = new Promise(resolve => { entered = result => { observed = result; resolve(); }; });
  const wait = team.wait.bind(team);
  team.wait = (...args) => { const result = wait(...args); entered(result); return result; };
  const request = remoteWait(team.url, 'Bearer bob', { agent: 'alice', timeout: 86400 });
  await started;
  team.event(team.agents.get('alice'), { type: 'agent_settled' });
  assert.equal((await request).reason, 'idle');
  team.change(team.agents.get('alice'), 'running');
  started = new Promise(resolve => { entered = result => { observed = result; resolve(); }; });
  const controller = new AbortController();
  const disconnected = assert.rejects(remoteWait(team.url, 'Bearer bob', { agent: 'alice' }, controller.signal), /abort/i);
  await started;
  controller.abort();
  await disconnected;
  assert.equal((await observed).reason, 'cancelled');
  assert.equal(team.waiters.size, 0);
  assert.equal(team.agents.get('alice').status, 'running');
});
