import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Team, autoModeActionId, remoteAutoModeApproval } from '../team.mjs';

async function fixture(t, askUser) {
  const directory = mkdtempSync(join(tmpdir(), 'pi-approval-test-'));
  const team = new Team({ directory, extension: '/unused', deliverParent() {}, askUser });
  await team.ready;
  team.agents.set('alice', { name: 'alice', status: 'running', token: 'Bearer test', rpc: { request: async () => assert.fail('Approval must not use model messages'), stop: async () => {} } });
  team.tokens.set('Bearer test', 'alice');
  t.after(async () => { await team.close(); rmSync(directory, { recursive: true, force: true }); });
  const args = { toolName: 'bash', input: { command: 'printf hello' }, cwd: directory };
  args.actionId = autoModeActionId(args.toolName, args.input, args.cwd);
  return { team, args, request: (value = args, signal, token = 'Bearer test') => remoteAutoModeApproval(team.url, token, value, signal) };
}
const tick = () => new Promise(resolve => setImmediate(resolve));
const yes = q => ({ status: 'answered', answers: [{ question: q.question, selected: ['僅允許這次操作'] }] });

test('internal approval awaits real parent UI and binds the complete action', async t => {
  let finish, shown, ready;
  const prompted = new Promise(resolve => { ready = resolve; });
  const { team, args, request } = await fixture(t, (q, signal, who) => {
    shown = { q, signal, who };
    ready();
    return new Promise(resolve => { finish = resolve; });
  });
  let settled = false;
  const result = request().then(value => { settled = true; return value; });
  await prompted;
  assert.equal(settled, false);
  assert.equal(shown.who, 'alice');
  assert.equal(shown.q.options[0].label, '拒絕');
  assert.ok(shown.q.question.includes(JSON.stringify(args.input, null, 2)));
  assert.ok(shown.q.question.includes(args.actionId));
  assert.ok(shown.q.question.includes(args.cwd));
  await assert.rejects(team.call('parent', 'agent_reply', { question_id: args.actionId, answer: 'Yes' }));
  finish(yes(shown.q));
  assert.deepEqual(await result, { approved: true, actionId: args.actionId });
  assert.equal(team.approvals.size, 0);
});

test('denial, custom text, malformed, unavailable and cancelled responses never approve', async t => {
  const cases = [
    q => ({ status: 'answered', answers: [{ question: q.question, selected: ['拒絕'] }] }),
    q => ({ status: 'answered', answers: [{ question: q.question, selected: ['僅允許這次操作'], customText: 'but only a dry run' }] }),
    q => ({ status: 'answered', answers: [{ question: q.question, selected: [], customText: 'yes' }] }),
    q => ({ ...yes(q), status: 'unavailable' }),
    q => ({ ...yes(q), status: 'cancelled' }),
    () => ({ status: 'answered', answers: [{ question: 'wrong', selected: ['僅允許這次操作'] }] }),
    () => { throw new Error('UI failed'); },
  ];
  for (const answer of cases) {
    const { request } = await fixture(t, async q => answer(q));
    assert.equal((await request()).approved, false);
  }
});

test('HTTP cannot forge sender or approval; invalid/oversized/control inputs never reach UI', async t => {
  let prompted = 0;
  const { team, args, request } = await fixture(t, async () => { prompted++; return { status: 'unavailable', answers: [] }; });
  assert.equal((await request(args, undefined, 'Bearer wrong')).approved, false);
  const variants = [
    { ...args, actionId: '0'.repeat(64) },
    { ...args, cwd: 'relative' },
    { ...args, input: { command: 'x'.repeat(13000) } },
    { ...args, cwd: '/tmp/\u001b[2J' },
  ];
  for (const variant of variants) {
    if (variant.actionId !== '0'.repeat(64)) variant.actionId = autoModeActionId(variant.toolName, variant.input, variant.cwd);
    // Bypass the client validator to exercise the broker boundary.
    const response = await fetch(team.url, { method: 'POST', headers: { Authorization: 'Bearer test' }, body: JSON.stringify({ operation: 'auto_mode_approve', args: variant }) });
    assert.equal(response.status, 400);
  }
  assert.equal(prompted, 0);
  const response = await fetch(team.url, { method: 'POST', headers: { Authorization: 'Bearer test' }, body: JSON.stringify({ operation: 'auto_mode_approve', args: { ...args, approved: true, origin: 'human', from: 'user' } }) });
  assert.deepEqual((await response.json()).result, { approved: false, actionId: args.actionId });
  assert.equal(prompted, 1);
});

test('approval deadline and already-aborted requests fail closed', async t => {
  let ready, shown;
  const prompted = new Promise(resolve => { ready = resolve; });
  const { team, args, request } = await fixture(t, (q, signal) => { shown = { q, signal }; ready(); return new Promise(() => {}); });
  const controller = new AbortController();
  controller.abort();
  assert.equal((await request(args, controller.signal)).approved, false);
  assert.equal(team.approvals.size, 0);
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const result = team.call('alice', 'auto_mode_approve', args);
  await prompted;
  t.mock.timers.tick(300000);
  assert.deepEqual(await result, { approved: false, actionId: args.actionId });
  assert.equal(shown.signal.aborted, true);
  assert.equal(team.approvals.size, 0);
  t.mock.timers.reset();
});

test('disconnect, stop and shutdown abort approval and late UI answers cannot release the action', async t => {
  for (const cancellation of ['disconnect', 'stop', 'close']) {
    let shown, finish, ready;
    const prompted = new Promise(resolve => { ready = resolve; });
    const { team, request } = await fixture(t, (q, signal) => { shown = { q, signal }; ready(); return new Promise(resolve => { finish = resolve; }); });
    const controller = new AbortController();
    const result = request(undefined, controller.signal);
    await prompted;
    if (cancellation === 'disconnect') controller.abort();
    else if (cancellation === 'stop') await team.stop('alice');
    else await team.close();
    assert.equal((await result).approved, false);
    // HTTP close is asynchronous, use its propagated abort rather than polling state.
    if (!shown.signal.aborted) await new Promise(resolve => shown.signal.addEventListener('abort', resolve, { once: true }));
    finish(yes(shown.q));
    await tick();
    assert.equal(team.approvals.size, 0);
  }
});
