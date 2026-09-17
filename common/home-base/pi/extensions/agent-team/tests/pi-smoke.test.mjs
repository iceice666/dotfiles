import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Team } from '../team.mjs';
import { RpcProcess } from '../rpc.mjs';

// Disabled until these legacy smoke tests use an isolated config and a fail-closed
// provider fixture. --offline alone does not prevent completion API requests.
test.skip('real Pi loads parent extension and command without any model request', async () => {
  const env = { ...process.env };
  for (const key of ['PI_TEAM_AGENT', 'PI_TEAM_URL', 'PI_TEAM_TOKEN', 'PI_TEAM_PARENT_PID']) delete env[key];
  const rpc = new RpcProcess('pi', ['--mode', 'rpc', '--offline', '--no-session', '-e', fileURLToPath(new URL('../index.ts', import.meta.url))], { env });
  try {
    const { commands } = await rpc.request('get_commands');
    assert.equal(commands.filter(c => c.name === 'team').length, 1);
    await rpc.request('prompt', { message: '/team' });
  } finally { await rpc.stop(); }
});

test.skip('real Pi worker handshake, persistent process, tool registration and HTTP board roundtrip; zero LLM calls', async () => {
  const directory = mkdtempSync(join(tmpdir(), 'pi-team-smoke-'));
  const cwd = join(directory, 'project');
  mkdirSync(join(cwd, '.pi', 'extensions'), { recursive: true });
  // This test-only extension handles ALL prompts before Pi reaches a provider.
  writeFileSync(join(cwd, '.pi', 'extensions', 'no-model.ts'), `export default function(pi) {
    pi.on('input', async () => {
      const names = pi.getAllTools().map(t => t.name);
      await fetch(process.env.PI_TEAM_URL, { method: 'POST', headers: {Authorization: process.env.PI_TEAM_TOKEN}, body: JSON.stringify({operation:'board_post',args:{topic:'smoke',body:JSON.stringify(names)}}) });
      return {action:'handled'};
    });
  }`);
  const team = new Team({ directory: join(directory, 'team'), extension: fileURLToPath(new URL('../index.ts', import.meta.url)), deliverParent() {} });
  // Resolve existing default model without sending a prompt or reading credentials.
  const probe = new RpcProcess('pi', ['--mode', 'rpc', '--offline', '--no-session'], {});
  try {
    const state = await probe.request('get_state');
    assert.ok(state.model, 'Smoke test requires a configured default model (no API calls are made)');
    await team.spawn({ name: 'worker', task: 'Intercepted by no-model test extension' }, { cwd, model: `${state.model.provider}/${state.model.id}`, thinking: 'off', trusted: true });
    const posts = await team.call('parent', 'board_read', { topic: 'smoke' });
    assert.equal(posts.items.length, 1);
    const tools = JSON.parse(posts.items[0].body);
    assert.ok(tools.includes('agent_ask')); assert.ok(tools.includes('board_post'));
    assert.ok(!tools.includes('agent_spawn')); assert.ok(!tools.includes('agent_stop'));
    await team.call('parent', 'agent_send', { to: 'worker', message: 'second turn' });
    assert.equal((await team.call('parent', 'board_read', { topic: 'smoke' })).items.length, 2);
    const worker = team.agents.get('worker');
    assert.equal(worker.rpc.closed, false);
    await team.stop('worker'); assert.equal(worker.rpc.closed, true);
  } finally { await probe.stop(); await team.close(); rmSync(directory, { recursive: true, force: true }); }
});
