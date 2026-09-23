import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Team, parseAgentKinds } from '../team.mjs';
import { RpcProcess } from '../rpc.mjs';

async function fixture(t) {
  const directory = mkdtempSync(join(tmpdir(), 'pi-team-test-'));
  const delivered = [];
  const team = new Team({ directory, extension: '/unused', deliverParent: e => delivered.push(e) });
  await team.ready;
  t.after(async () => { await team.close(); rmSync(directory, { recursive: true, force: true }); });
  const messages = [];
  team.agents.set('alice', { name: 'alice', status: 'idle', token: 'Bearer test', rpc: { request: async (...args) => messages.push(args), stop: async () => {} } });
  team.tokens.set('Bearer test', 'alice');
  return { team, delivered, messages };
}

test('agent kind configuration is validated and merged with defaults', () => {
  assert.deepEqual(parseAgentKinds('{"reviewer":{"model":"custom/model","thinking":"high"}}').reviewer, { model: 'custom/model', thinking: 'high' });
  assert.equal(parseAgentKinds('{"scout":{"thinking":"minimal"}}').scout.thinking, 'minimal');
  assert.throws(() => parseAgentKinds('{"bad":{"unknown":true}}'), /Unknown agent kind fields/);
  assert.throws(() => parseAgentKinds('{"bad":{"thinking":"invalid"}}'), /Invalid thinking level/);
});

test('question -> parent -> reply wakes child; identities and duplicates enforced', async t => {
  const { team, delivered, messages } = await fixture(t);
  const q = await team.call('alice', 'agent_ask', { question: 'Which API?' });
  assert.equal(delivered[0].id, q.id);
  await assert.rejects(team.call('alice', 'agent_reply', { question_id: q.id, answer: 'spoof' }));
  await team.call('parent', 'agent_reply', { question_id: q.id, answer: 'v2' });
  assert.equal(messages[0][1].streamingBehavior, 'steer');
  assert.match(messages[0][1].message, /v2/);
  await assert.rejects(team.call('parent', 'agent_reply', { question_id: q.id, answer: 'again' }));
  assert.match(readFileSync(join(team.directory, 'events.jsonl'), 'utf8'), /question_id/);
});

test('agent kinds route preset model and thinking while explicit values override', async t => {
  const { team } = await fixture(t);
  assert.deepEqual(team.list().kinds, ['general', 'scout', 'researcher']);
  team.executable = '/nonexistent-pi-team-executable';
  const defaults = { cwd: team.directory, model: 'parent/model', thinking: 'high' };
  await assert.rejects(team.spawn({ name: 'scout-one', kind: 'scout', task: 'scan' }, defaults));
  const scout = team.agents.get('scout-one');
  assert.equal(scout.model, 'cliproxyapi/gpt-6-sol');
  assert.equal(scout.thinking, 'low');
  await assert.rejects(team.spawn({ name: 'custom-one', kind: 'researcher', model: 'custom/model', thinking: 'off', task: 'research' }, defaults));
  const custom = team.agents.get('custom-one');
  assert.equal(custom.model, 'custom/model');
  assert.equal(custom.thinking, 'off');
  await assert.rejects(team.spawn({ name: 'missing-kind', kind: 'missing', task: 'x' }, defaults), /Unknown agent kind/);
});

test('automatic worker reports are bounded while archive keeps full body', async t => {
  const { team, delivered } = await fixture(t);
  const worker = team.agents.get('alice');
  const body = 'x'.repeat(4000);
  team.event(worker, { type: 'message_end', message: { role: 'assistant', content: [{ type: 'text', text: body }], stopReason: 'stop' } });
  assert.ok(delivered.at(-1).body.length < body.length);
  assert.match(delivered.at(-1).body, /Preview truncated/);
  assert.equal(team.records.at(-1).body, body);
});
test('peer messaging, stop authorization, missing recipients', async t => {
  const { team, messages } = await fixture(t);
  await team.call('parent', 'agent_send', { to: 'alice', message: 'hello' });
  assert.equal(messages.length, 1);
  team.agents.set('bob', { name: 'bob', status: 'idle' });
  await team.call('bob', 'agent_send', { to: 'alice', message: 'peer update' });
  assert.equal(messages.length, 2);
  assert.match(messages[1][1].message, /bob/);
  await assert.rejects(team.call('alice', 'agent_stop', { agent: 'alice' }));
  await assert.rejects(team.call('parent', 'agent_send', { to: 'missing', message: 'hi' }));
  await team.stop('alice');
  await assert.rejects(team.call('parent', 'agent_send', { to: 'alice', message: 'hi' }));
});
test('board append, topic filtering, cursors and size limits', async t => {
  const { team } = await fixture(t);
  await Promise.all(Array.from({ length: 12 }, (_, i) => team.call('alice', 'board_post', { topic: 'auth', body: `note ${i}` })));
  const first = await team.call('parent', 'board_read', { topic: 'auth', limit: 5 });
  assert.equal(first.items.length, 5); assert.equal(first.more, true);
  const second = await team.call('parent', 'board_read', { topic: 'auth', after: first.next });
  assert.equal(second.items.length, 7); assert.equal(second.more, false);
  await assert.rejects(team.call('alice', 'board_post', { topic: 'auth', body: 'x'.repeat(12001) }));
  await assert.rejects(team.call('alice', 'board_read', { after: 'invalid' }));
});
test('HTTP binds localhost, authenticates sender, disallows remote spawn', async t => {
  const { team } = await fixture(t);
  assert.equal((await fetch(team.url, { method: 'POST' })).status, 401);
  const req = operation => fetch(team.url, { method: 'POST', headers: { Authorization: 'Bearer test' }, body: JSON.stringify({ operation, args: { topic: 'x', body: 'hello', from: 'parent' } }) });
  const post = await (await req('board_post')).json();
  assert.equal(post.result.from, 'alice');
  assert.equal((await req('agent_spawn')).status, 400);
});
test('failed answer delivery is recorded and retryable', async t => {
  const { team } = await fixture(t);
  const q = await team.call('alice', 'agent_ask', { question: 'Which version?' });
  const rpc = team.agents.get('alice').rpc;
  const original = rpc.request;
  rpc.request = async () => { throw new Error('not accepted'); };
  await assert.rejects(team.call('parent', 'agent_reply', { question_id: q.id, answer: 'v2' }), /not accepted/);
  rpc.request = original;
  await team.call('parent', 'agent_reply', { question_id: q.id, answer: 'v2' });
  assert.ok(team.records.some(r => r.kind === 'delivery_failed'));
});
test('spawn validates names/capacity/cancellation and cleans failed executable', async t => {
  const { team } = await fixture(t);
  const defaults = { cwd: team.directory, model: 'test/model', thinking: 'off' };
  await assert.rejects(team.spawn({ name: '../escape', task: 'x' }, defaults));
  await assert.rejects(team.spawn({ name: 'parent', task: 'x' }, defaults));
  const controller = new AbortController(); controller.abort();
  await assert.rejects(team.spawn({ name: 'cancelled', task: 'x' }, defaults, controller.signal));
  assert.equal(team.agents.has('cancelled'), false);
  team.limit = 1;
  await assert.rejects(team.spawn({ name: 'extra', task: 'x' }, defaults), /Limit/);
  team.limit = 4; team.executable = '/nonexistent-pi-team-executable';
  const published = [];
  team.onChange = state => published.push(state.agents.find(a => a.name === 'broken')?.status);
  await assert.rejects(team.spawn({ name: 'broken', task: 'x' }, defaults));
  assert.equal(published[0], 'starting');
  assert.equal(published.at(-1), 'failed');
  assert.equal(team.agents.get('broken').status, 'failed');
  assert.equal(team.tokens.size, 1);
});
test('terminal state notifications preserve archived workers and observations', async t => {
  const { team } = await fixture(t);
  const states = [];
  team.onChange = state => states.push(state);
  const alice = team.agents.get('alice');
  team.event(alice, { type: 'team_exit', code: 0, stderr: '' });
  assert.equal(states.at(-1).agents[0].status, 'failed');
  assert.equal(team.list().agents[0].name, 'alice');
  assert.ok(team.observeNative('alice'));
  await team.stop('alice');
  assert.equal(states.at(-1).agents[0].status, 'stopped');
  assert.ok(team.observeNative('alice'));
});

test('waiting status follows unresolved questions; retries do not report premature idle', async t => {
  const { team } = await fixture(t);
  const a = team.agents.get('alice');
  const q = await team.call('alice', 'agent_ask', { question: 'Need guidance' });
  team.event(a, { type: 'agent_start' });
  team.event(a, { type: 'agent_end', willRetry: true });
  assert.equal(a.status, 'running');
  team.event(a, { type: 'agent_settled' }); assert.equal(a.status, 'waiting');
  await team.call('parent', 'agent_reply', { question_id: q.id, answer: 'Proceed' });
  team.event(a, { type: 'agent_settled' }); assert.equal(a.status, 'idle');
});
test('RPC strict LF framing, correlation, rejection, process cleanup', async () => {
  const source = `process.stdin.setEncoding('utf8'); let b=''; process.stdin.on('data', c=>{b+=c; let i; while((i=b.indexOf('\\n'))>=0){ const q=JSON.parse(b.slice(0,i)); b=b.slice(i+1); process.stdout.write(JSON.stringify({type:'response',id:q.id,success:q.type!=='bad',error:'bad',data:{text:'a\\u2028b\\u2029中文'}})+'\\n'); }});`;
  const rpc = new RpcProcess(process.execPath, ['-e', source], {});
  try {
    assert.equal((await rpc.request('get_state')).text, 'a\u2028b\u2029中文');
    await assert.rejects(rpc.request('bad'), /bad/);
  } finally { await rpc.stop(); }
  assert.equal(rpc.closed, true); assert.equal(rpc.pending.size, 0);
});
test('RPC timeout and unexpected exit reject outstanding requests', async () => {
  const rpc = new RpcProcess(process.execPath, ['-e', 'setInterval(()=>{},1000)'], {});
  await assert.rejects(rpc.request('silent', {}, 20), /timed out/);
  const pending = assert.rejects(rpc.request('pending'), /exited/);
  await rpc.stop(); await pending;
});
