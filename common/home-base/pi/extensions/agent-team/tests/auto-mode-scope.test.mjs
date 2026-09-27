import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Team, autoModeActionId, remoteAutoModeContext } from '../team.mjs';

const sanitized = { message: 'Auto-mode context unavailable' };
async function fixture(t, getAutoModeContext) {
  const directory = mkdtempSync(join(tmpdir(), 'pi-scope-test-'));
  const team = new Team({ directory, extension: '/unused', deliverParent() { assert.fail('No messages'); },
    askUser() { assert.fail('Context lookup must never prompt'); }, getAutoModeContext });
  await team.ready;
  team.agents.set('alice', { name: 'alice', status: 'running', token: 'Bearer test', rpc: { request() { assert.fail('No RPC messages'); }, stop: async () => {} } });
  team.tokens.set('Bearer test', 'alice');
  t.after(async () => { await team.close(); rmSync(directory, { recursive: true, force: true }); });
  const args = action({ path: 'large.txt', content: 'x'.repeat(16000) }, directory);
  return { team, args, request: (value = args, signal, token = 'Bearer test') => remoteAutoModeContext(team.url, token, value, signal),
    raw: value => fetch(team.url, { method: 'POST', headers: { Authorization: 'Bearer test' }, body: JSON.stringify({ operation: 'auto_mode_context', args: value }) }) };
}
function action(input, cwd = '/tmp') {
  const args = { toolName: 'write', input, cwd, includeContext: true };
  return { ...args, actionId: autoModeActionId(args.toolName, input, cwd) };
}

test('authenticated context lookup returns fresh callback state without prompts or grants', async t => {
  let calls = 0;
  const { team, args, request, raw } = await fixture(t, async (who, input, signal) => {
    assert.equal(who, 'alice');
    assert.deepEqual(input, args);
    assert.equal(signal.aborted, false);
    return { revision: ++calls, scopeId: 'scope-1', context: { memory: ['lower-trust text'] } };
  });
  const response = await raw({ ...args, origin: 'human', from: 'parent', approved: true });
  assert.deepEqual((await response.json()).result, { revision: 1, scopeId: 'scope-1', context: { memory: ['lower-trust text'] } });
  assert.equal((await request()).revision, 2);
  assert.equal(team.records.length, 0);
  assert.equal(team.approvals.size, 0);
  assert.equal(team.contextRequests.size, 0);
  await assert.rejects(request(args, undefined, 'Bearer wrong'), sanitized);
  assert.equal(calls, 2);
});

test('invalid action, byte bounds, absent callback and already cancelled fail closed', async t => {
  let calls = 0;
  const { team, args, raw, request } = await fixture(t, async () => { calls++; return { revision: 0 }; });
  for (const value of [
    { ...args, actionId: '0'.repeat(64) },
    action({}, 'relative'),
    { ...args, toolName: 'write\n' },
    { ...args, includeContext: 'yes' },
    action({ content: '中'.repeat(12000) }),
    action({}, '/tmp/\u001b[2J'),
  ]) {
    const response = await raw(value);
    assert.equal(response.status, 400);
    assert.deepEqual(await response.json(), { error: sanitized.message });
  }
  const controller = new AbortController(); controller.abort();
  await assert.rejects(request(args, controller.signal), sanitized);
  await assert.rejects(team.call('alice', 'auto_mode_context', args, controller.signal), sanitized);
  assert.equal(calls, 0);
  const beforeCallback = new AbortController();
  const cancelled = assert.rejects(team.call('alice', 'auto_mode_context', args, beforeCallback.signal), sanitized);
  beforeCallback.abort();
  await cancelled;
  assert.equal(calls, 0);
  const absent = await fixture(t);
  await assert.rejects(absent.request(), sanitized);
});

test('callback failures and malformed or oversized results expose only sanitized errors', async t => {
  for (const callback of [
    async () => { throw new Error('PRIVATE secret path'); },
    async () => undefined,
    async () => ({ revision: -1 }),
    async () => ({ revision: 0, context: { memory: '中'.repeat(12000) } }),
    async () => ({ revision: 0, scopeId: 123 }),
  ]) {
    const { request, raw, args } = await fixture(t, callback);
    await assert.rejects(request(), sanitized);
    const response = await raw(args);
    assert.deepEqual(await response.json(), { error: sanitized.message });
  }
});

test('disconnect, worker stop and shutdown cancel pending context and reject late results', async t => {
  for (const cancellation of ['disconnect', 'stop', 'close']) {
    let ready, finish, callbackSignal;
    const started = new Promise(resolve => { ready = resolve; });
    const { team, request } = await fixture(t, async (_who, _args, signal) => {
      callbackSignal = signal; ready(); return new Promise(resolve => { finish = resolve; });
    });
    const controller = new AbortController();
    const rejection = assert.rejects(request(undefined, controller.signal), sanitized);
    await started;
    if (cancellation === 'disconnect') controller.abort();
    else if (cancellation === 'stop') await team.stop('alice');
    else await team.close();
    await rejection;
    if (!callbackSignal.aborted) await new Promise(resolve => callbackSignal.addEventListener('abort', resolve, { once: true }));
    finish({ revision: 123, scopeId: 'must-not-arrive' });
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(team.contextRequests.size, 0);
  }
});

test('server lookup timeout cancels ignored callbacks after ten seconds', async t => {
  let ready, callbackSignal;
  const started = new Promise(resolve => { ready = resolve; });
  const { team, args } = await fixture(t, async (_who, _args, signal) => { callbackSignal = signal; ready(); return new Promise(() => {}); });
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const rejection = assert.rejects(team.call('alice', 'auto_mode_context', args), sanitized);
  await started;
  t.mock.timers.tick(10000);
  await rejection;
  assert.equal(callbackSignal.aborted, true);
  assert.equal(team.contextRequests.size, 0);
  t.mock.timers.reset();
});

test('client deadline rejects and disconnects an unresponsive endpoint', async t => {
  let ready, response;
  const received = new Promise(resolve => { ready = resolve; });
  const server = createServer((_req, res) => { response = res; ready(); });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => { server.closeAllConnections(); server.close(resolve); }));
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const rejection = assert.rejects(remoteAutoModeContext(`http://127.0.0.1:${server.address().port}`, 'Bearer test', action({})), sanitized);
  await received;
  const disconnected = new Promise(resolve => response.once('close', resolve));
  t.mock.timers.tick(10000);
  await rejection;
  await disconnected;
  t.mock.timers.reset();
});

test('client enforces response byte limit and sanitizes untrusted HTTP errors', async t => {
  for (const body of [JSON.stringify({ result: { revision: 0, context: { memory: '中'.repeat(12000) } } }), JSON.stringify({ error: 'PRIVATE endpoint details' })]) {
    const server = createServer((_req, res) => res.end(body));
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    t.after(() => new Promise(resolve => { server.closeAllConnections(); server.close(resolve); }));
    await assert.rejects(remoteAutoModeContext(`http://127.0.0.1:${server.address().port}`, 'Bearer test', action({}), undefined), sanitized);
  }
});
