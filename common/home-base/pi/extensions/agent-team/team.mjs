import { createServer, request } from 'node:http';
import { randomUUID, randomBytes } from 'node:crypto';
import { mkdirSync, appendFileSync, writeFileSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { RpcProcess } from './rpc.mjs';
import { Observation, safeText } from './observation.mjs';
import { NativeObservation } from './native-observation.mjs';

const THINKING_LEVELS = new Set(['off', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max']);
const KIND_NAME = /^[a-z][a-z0-9_-]{0,39}$/;
const DEFAULT_AGENT_KINDS = {
  general: {},
  scout: { model: 'cliproxyapi/gpt-5.6-sol', thinking: 'low' },
  researcher: { model: 'cliproxyapi/gpt-5.6-sol', thinking: 'medium' },
};
const RESULT_NOTICE_LIMIT = 2000;

function validateKindPresets(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Agent kinds must be an object');
  const result = {};
  for (const [kind, preset] of Object.entries(value)) {
    if (!KIND_NAME.test(kind) || ['parent', 'user'].includes(kind)) throw new Error(`Invalid agent kind: ${kind}`);
    if (!preset || typeof preset !== 'object' || Array.isArray(preset)) throw new Error(`Invalid agent kind preset: ${kind}`);
    const unknown = Object.keys(preset).filter(key => !['model', 'thinking'].includes(key));
    if (unknown.length) throw new Error(`Unknown agent kind fields for ${kind}: ${unknown.join(', ')}`);
    const model = preset.model;
    const thinking = preset.thinking;
    if (model !== undefined && (typeof model !== 'string' || !model.trim() || model.length > 200)) throw new Error(`Invalid model for agent kind: ${kind}`);
    if (thinking !== undefined && (typeof thinking !== 'string' || !THINKING_LEVELS.has(thinking))) throw new Error(`Invalid thinking level for agent kind: ${kind}`);
    result[kind] = { ...(model === undefined ? {} : { model }), ...(thinking === undefined ? {} : { thinking }) };
  }
  return result;
}

export function parseAgentKinds(raw = process.env.PI_TEAM_KINDS) {
  if (raw === undefined || raw === '') return { ...DEFAULT_AGENT_KINDS };
  if (typeof raw !== 'string') throw new Error('PI_TEAM_KINDS must be a JSON string');
  const source = raw.trim();
  if (!source) return { ...DEFAULT_AGENT_KINDS };
  if (source.length > 16000) throw new Error('PI_TEAM_KINDS is too large');
  let parsed;
  try { parsed = JSON.parse(source); } catch { throw new Error('PI_TEAM_KINDS must be valid JSON'); }
  return { ...DEFAULT_AGENT_KINDS, ...validateKindPresets(parsed) };
}

function compactResult(entry) {
  const body = typeof entry.body === 'string' ? entry.body : String(entry.body ?? '');
  const normalized = body.replace(/[ \t]+/g, ' ').replace(/\n{3,}/g, '\n\n').trim();
  const clipped = normalized.length > RESULT_NOTICE_LIMIT;
  const preview = normalized.slice(0, RESULT_NOTICE_LIMIT);
  return {
    ...entry,
    body: `${preview}${clipped ? '\n[Preview truncated]' : ''}\nFull result: agent_inbox event ${entry.id}`,
    ...(clipped ? { truncated: true } : {}),
  };
}

const active = a => !['stopped', 'failed'].includes(a.status);
export function text(value, label = 'text', max = 12000) {
  if (typeof value !== 'string' || !value.trim() || value.length > max) throw new Error(`${label} must contain 1–${max} characters`);
  return value;
}
// HTTP callers bypass Pi's tool schema. Copy only validated question fields.
export function userQuestion(args) {
  const question = { question: text(args.question, 'question') };
  if (args.header !== undefined) {
    if (typeof args.header !== 'string' || args.header.length > 120) throw new Error('Invalid question header');
    question.header = args.header;
  }
  if (args.multiSelect !== undefined) {
    if (typeof args.multiSelect !== 'boolean') throw new Error('multiSelect must be boolean');
    question.multiSelect = args.multiSelect;
  }
  if (args.options !== undefined) {
    if (!Array.isArray(args.options) || args.options.length > 12) throw new Error('options must be an array of at most 12 options');
    question.options = args.options.map(option => {
      if (!option || typeof option !== 'object' || Array.isArray(option)) throw new Error('Invalid option');
      const result = { label: text(option.label, 'option label', 1000) };
      if (option.description !== undefined) {
        if (typeof option.description !== 'string' || option.description.length > 4000) throw new Error('Invalid option description');
        result.description = option.description;
      }
      return result;
    });
    if (new Set(question.options.map(o => o.label)).size !== question.options.length) throw new Error('Option labels must be unique');
  }
  if (JSON.stringify({ questions: [question] }).length > 24000) throw new Error('Questionnaire exceeds 24000 characters');
  const unsafe = /[\u0000-\u0008\u000b-\u001f\u007f-\u009f]/;
  if ([question.question, question.header, ...(question.options ?? []).flatMap(o => [o.label, o.description])].some(value => value && unsafe.test(value))) throw new Error('Question text must not contain terminal control characters');
  return question;
}
// Unlike fetch's default headers timeout, this transport supports a full-day wait.
export function remoteWait(url, token, args, signal) {
  return new Promise((resolve, reject) => {
    const req = request(url, { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: token }, signal }, res => {
      let body = '';
      res.setEncoding('utf8');
      res.on('data', chunk => {
        body += chunk;
        if (body.length > 64000) req.destroy(new Error('Team response too large'));
      });
      res.on('error', reject);
      res.on('end', () => {
        try {
          const data = JSON.parse(body);
          if (res.statusCode !== 200 || data.error) throw new Error(data.error || `Team HTTP ${res.statusCode}`);
          resolve(data.result);
        } catch (error) { reject(error); }
      });
    });
    const seconds = typeof args?.timeout === 'number' && Number.isFinite(args.timeout) ? Math.max(0, Math.min(86400, args.timeout)) : 60;
    const deadline = setTimeout(() => req.destroy(new Error('Team wait transport timed out')), (seconds + 5) * 1000);
    req.once('close', () => clearTimeout(deadline));
    req.on('error', reject);
    req.end(JSON.stringify({ operation: 'agent_wait', args }));
  });
}
export class Team {
  constructor({ directory, extension, deliverParent, executable = 'pi', limit = 4, onChange = () => {}, askUser = async () => ({ status: 'unavailable', answers: [] }), kinds }) {
    this.directory = directory; this.extension = extension; this.deliverParent = deliverParent;
    this.executable = executable; this.limit = limit; this.onChange = onChange;
    this.kinds = kinds === undefined ? parseAgentKinds() : { ...DEFAULT_AGENT_KINDS, ...validateKindPresets(kinds) };
    this.askUser = askUser; this.userQuestions = new Map();
    this.agents = new Map(); this.tokens = new Map(); this.records = []; this.closing = false;
    this.waiters = new Set();
    mkdirSync(directory, { recursive: true, mode: 0o700 });
    this.server = createServer(async (req, res) => {
      try {
        const who = this.tokens.get(req.headers.authorization);
        if (!who) { res.writeHead(401).end(); return; }
        if (req.method !== 'POST' || req.url !== '/call') { res.writeHead(404).end(); return; }
        let body = ''; req.setEncoding('utf8');
        for await (const chunk of req) { body += chunk; if (body.length > 64000) throw new Error('Request too large'); }
        const { operation, args } = JSON.parse(body);
        const controller = new AbortController();
        const disconnected = () => controller.abort();
        res.once('close', disconnected);
        try {
          const result = await this.call(who, operation, args ?? {}, controller.signal);
          res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify({ result }));
        } finally { res.removeListener('close', disconnected); }
      } catch (e) { res.writeHead(400, { 'Content-Type': 'application/json' }).end(JSON.stringify({ error: String(e.message) })); }
    });
    this.server.requestTimeout = 10000;
    this.ready = new Promise((yes, no) => {
      this.server.once('error', no);
      this.server.listen(0, '127.0.0.1', () => { this.url = `http://127.0.0.1:${this.server.address().port}/call`; yes(); });
    });
  }
  record(kind, data) {
    const entry = { id: randomUUID(), time: new Date().toISOString(), kind, ...data };
    appendFileSync(join(this.directory, 'events.jsonl'), JSON.stringify(entry) + '\n', { mode: 0o600 });
    this.records.push(entry); this.notifyWaiters(); return entry;
  }
  list() {
    return { directory: this.directory, kinds: Object.keys(this.kinds ?? {}), agents: [...this.agents.values()].map(({ name, kind, status, cwd, model, thinking, sessionFile, lastError, task, pid, startedAt, lastActivity, activity }) => ({ name, ...(kind ? { kind } : {}), status, cwd, model, thinking, sessionFile, lastError, task, pid, startedAt, lastActivity, activity })) };
  }
  observe(name) {
    const a = this.agents.get(name);
    if (!a) throw new Error('Unknown agent');
    return a.observation?.snapshot() ?? { text: '', revision: 0 };
  }
  observeNative(name) {
    const a = this.agents.get(name);
    if (!a) throw new Error('Unknown agent');
    a.nativeObservation ??= new NativeObservation();
    return a.nativeObservation.snapshot();
  }
  change(a, status) {
    a.status = status; a.activity = status; a.lastActivity = new Date().toISOString();
    a.stateRevision = (a.stateRevision ?? 0) + 1;
    this.notifyWaiters();
    this.onChange(this.list());
  }
  notifyWaiters() {
    for (const waiter of [...this.waiters]) waiter.check();
  }
  wait(who, args, signal) {
    const name = text(args.agent, 'agent', 40);
    if (name === who) throw new Error('Cannot wait for yourself');
    const a = this.agents.get(name);
    if (!a) throw new Error(`Unknown worker agent: ${name}; parent cannot be waited on`);
    const timeout = args.timeout ?? 60;
    if (typeof timeout !== 'number' || !Number.isFinite(timeout) || timeout <= 0 || timeout > 86400) throw new Error('timeout must be seconds greater than 0 and at most 86400');
    // A caller can issue parallel waits; follow every edge to reject cycles.
    const reaches = (from, seen = new Set()) => {
      if (from === who) return true;
      if (seen.has(from)) return false;
      seen.add(from);
      return [...this.waiters].some(w => w.who === from && reaches(w.agent, seen));
    };
    if (reaches(name)) throw new Error('Wait would create a dependency cycle');
    return new Promise(resolve => {
      let timer, settled = false;
      const finish = (reason, question) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        signal?.removeEventListener('abort', abort);
        this.waiters.delete(waiter);
        resolve({ agent: name, reason, status: a.status, question_id: question?.id, question_to: question?.to, sessionFile: a.sessionFile });
      };
      const abort = () => finish('cancelled');
      const waiter = { who, agent: name, check: () => {
        if (signal?.aborted) return finish('cancelled');
        if (this.closing) return finish('closed');
        if (who !== 'parent' && !active(this.agents.get(who) ?? { status: 'stopped' })) return finish('caller_stopped');
        if (!active(a)) return finish(a.status);
        const question = this.records.find(q => q.kind === 'question' && (q.to === who || q.from === name)
          && (q.from === 'parent' || active(this.agents.get(q.from) ?? { status: 'stopped' }))
          && !this.records.some(r => r.kind === 'reply' && r.question_id === q.id && !this.records.some(f => f.kind === 'delivery_failed' && f.message_id === r.id)));
        if (question) return finish('question', question);
        if (a.status === 'waiting') return finish('blocked');
        if (a.status === 'idle') return finish('idle');
      } };
      this.waiters.add(waiter);
      timer = setTimeout(() => finish('timeout'), timeout * 1000);
      signal?.addEventListener('abort', abort, { once: true });
      waiter.check();
    });
  }
  async spawn(args, defaults, signal) {
    if (this.closing) throw new Error('Team shutting down');
    const name = text(args.name, 'name', 40);
    if (!/^[a-z][a-z0-9_-]*$/.test(name) || ['parent', 'user'].includes(name)) throw new Error('Use a lowercase agent name; parent and user are reserved');
    if (this.agents.has(name)) throw new Error('Name already used in this team');
    if ([...this.agents.values()].filter(active).length >= this.limit) throw new Error(`Limit of ${this.limit} live agents reached`);
    const task = text(args.task, 'task');
    const cwd = resolve(defaults.cwd, args.cwd ?? '.');
    if (!statSync(cwd).isDirectory()) throw new Error('cwd must be a directory');
    const kind = args.kind ?? 'general';
    if (typeof kind !== 'string' || !this.kinds[kind]) throw new Error(`Unknown agent kind: ${kind}`);
    const preset = this.kinds[kind];
    const model = args.model ?? preset.model ?? defaults.model;
    if (!model) throw new Error('Select a parent model or provide provider/model');
    const thinking = args.thinking ?? preset.thinking ?? defaults.thinking ?? 'off';
    if (!THINKING_LEVELS.has(thinking)) throw new Error('Invalid thinking level');
    signal?.throwIfAborted();
    const startedAt = new Date().toISOString();
    const a = { name, kind, cwd, model, thinking, task, startedAt, lastActivity: startedAt, activity: 'starting', status: 'starting', observation: new Observation() };
    this.agents.set(name, a); // Reserve before awaiting: parallel spawn calls obey the limit.
    const token = `Bearer ${randomBytes(32).toString('hex')}`;
    a.token = token; this.tokens.set(token, name);
    const dir = join(this.directory, name); mkdirSync(dir, { mode: 0o700 });
    const abort = () => { if (a.rpc) void this.stop(name); };
    signal?.addEventListener('abort', abort, { once: true });
    try {
      this.change(a, 'starting');
      await this.ready;
      signal?.throwIfAborted();
      if (this.closing || a.status === 'stopped') throw new Error('Agent stopped during startup');
      const cli = ['--mode', 'rpc', '--offline', '--model', model, '--thinking', thinking, '--session-dir', dir, '--name', `team:${name}`, '-e', this.extension];
      // Do not grant a different working directory the parent's temporary trust.
      if (cwd === resolve(defaults.cwd)) cli.push(defaults.trusted ? '--approve' : '--no-approve');
      else cli.push('--no-approve');
      a.rpc = new RpcProcess(this.executable, cli, { cwd, env: { ...process.env, PI_TEAM_URL: this.url, PI_TEAM_TOKEN: token, PI_TEAM_AGENT: name, PI_TEAM_PARENT_PID: String(process.pid) } }, e => this.event(a, e));
      a.pid = a.rpc.child.pid;
      const state = await a.rpc.request('get_state');
      if (this.closing || a.status === 'stopped') throw new Error('Agent stopped during startup');
      a.sessionFile = state.sessionFile;
      this.record('spawn', { name, cwd, model, thinking, sessionFile: a.sessionFile });
      this.change(a, 'running');
      await this.send('parent', name, task, 'task');
      signal?.throwIfAborted();
      return this.list().agents.find(item => item.name === name);
    } catch (e) {
      a.lastError = String(e.message); this.change(a, 'failed'); this.tokens.delete(token);
      if (a.rpc) await a.rpc.stop();
      throw e;
    } finally { signal?.removeEventListener('abort', abort); }
  }
  event(a, e) {
    // Capture shutdown-time final output as well; observing never sends RPC commands.
    a.observation ??= new Observation();
    a.observation.ingest(e);
    a.nativeObservation ??= new NativeObservation();
    a.nativeObservation.ingest(e);
    a.lastActivity = new Date().toISOString();
    if (this.closing || a.status === 'stopped') return;
    if (e.type === 'message_update') a.activity = e.assistantMessageEvent?.type?.startsWith('thinking') ? 'thinking' : 'responding';
    if (e.type === 'tool_execution_start' || e.type === 'tool_execution_update') a.activity = `tool: ${safeText(e.toolName ?? 'tool').slice(0, 120)}`;
    if (e.type === 'tool_execution_end') a.activity = 'running';
    if (e.type === 'agent_start') this.change(a, 'running');
    if (e.type === 'agent_settled') {
      const pending = this.records.some(r => r.kind === 'question' && r.from === a.name && !this.records.some(x => x.kind === 'reply' && x.question_id === r.id && !this.records.some(f => f.kind === 'delivery_failed' && f.message_id === x.id)));
      this.change(a, pending ? 'waiting' : 'idle');
    }
    if (e.type === 'message_end' && e.message?.role === 'assistant') {
      const m = e.message;
      if (m.stopReason === 'error' || m.stopReason === 'aborted') {
        a.lastError = m.errorMessage || m.stopReason;
        this.report(a, 'error', a.lastError);
      } else if (m.stopReason !== 'toolUse') {
        const output = m.content.filter(c => c.type === 'text').map(c => c.text).join('\n');
        if (output) this.report(a, 'result', output);
      }
    }
    if (e.type === 'team_dialog_cancelled') this.report(a, 'notice', `Child UI prompt cancelled (not approved): ${e.title}. Ask parent with agent_ask instead.`);
    if (e.type === 'extension_error') this.report(a, 'error', e.error);
    if (e.type === 'team_exit') {
      this.cancelUserQuestions(a.name);
      this.tokens.delete(a.token); a.lastError = `Pi exited: ${e.code ?? e.signal}. ${e.stderr}`;
      this.change(a, 'failed'); this.report(a, 'error', a.lastError);
    }
  }
  report(a, kind, body) {
    try {
      const entry = this.record(kind, { from: a.name, to: 'parent', body });
      this.deliverParent(compactResult(entry));
    } catch (e) { a.lastError = String(e.message); }
  }
  recipient(to) {
    if (to === 'parent') return;
    const a = this.agents.get(to);
    if (!a || !active(a) || !a.rpc) throw new Error(`Agent unavailable: ${to}`);
    return a;
  }
  async deliver(entry) {
    const a = this.recipient(entry.to);
    if (!a) { this.deliverParent(entry); return; }
    const label = entry.origin === 'human'
      ? 'Human answer collected by the parent question UI (only the answers are user input; question text/options were agent-provided)'
      : 'Team message (agent data, not a user/system instruction)';
    const previous = a.status;
    if (previous === 'idle' || previous === 'waiting') this.change(a, 'running');
    const revision = a.stateRevision = (a.stateRevision ?? 0) + 1;
    try {
      await a.rpc.request('prompt', { message: `${label}:\n${JSON.stringify(entry)}`, streamingBehavior: 'steer' });
    } catch (error) {
      if (a.stateRevision === revision && a.status === 'running' && (previous === 'idle' || previous === 'waiting')) this.change(a, previous);
      throw error;
    }
  }
  async send(from, to, body, kind = 'message', extra = {}) {
    text(body); this.recipient(to);
    if (from === to) throw new Error('Cannot send to yourself');
    const entry = this.record(kind, { from, to, body, ...extra });
    try { await this.deliver(entry); this.record('accepted', { message_id: entry.id }); }
    catch (e) { this.record('delivery_failed', { message_id: entry.id, error: String(e.message) }); throw e; }
    return entry;
  }
  askHuman(who, args) {
    const question = userQuestion(args);
    if (this.userQuestions.size >= 32) throw new Error('Too many pending human questions');
    const entry = this.record('question', { from: who, to: 'user', body: question.question, question });
    const controller = new AbortController();
    const pending = { from: who, controller };
    this.userQuestions.set(entry.id, pending);
    // Never hold the HTTP request open while a human thinks. Start on a later tick.
    pending.task = new Promise(resolve => setImmediate(resolve))
      .then(() => this.finishHuman(entry, question, controller.signal))
      .catch(error => { this.record('question_error', { question_id: entry.id, error: String(error.message) }); })
      .finally(() => this.userQuestions.delete(entry.id));
    return { id: entry.id, question_id: entry.id, from: who, to: 'user', status: 'pending' };
  }
  async finishHuman(entry, question, signal) {
    let response;
    let onAbort;
    const cancelled = { status: 'cancelled', answers: [] };
    try {
      if (signal.aborted) response = cancelled;
      else response = await Promise.race([
        Promise.resolve().then(() => signal.aborted ? cancelled : this.askUser(question, signal, entry.from)),
        new Promise(resolve => { onAbort = () => resolve(cancelled); signal.addEventListener('abort', onAbort, { once: true }); }),
      ]);
    } catch {
      response = { status: 'unavailable', answers: [] };
    } finally {
      if (onAbort) signal.removeEventListener('abort', onAbort);
    }
    if (signal.aborted) response = cancelled;
    if (!['answered', 'cancelled', 'unavailable'].includes(response?.status)) response = { status: 'unavailable', answers: [] };
    if (response.status !== 'answered') response = { status: response.status, answers: [] };
    const reply = this.record('reply', {
      from: response.status === 'answered' ? 'user' : 'team', to: entry.from,
      origin: response.status === 'answered' ? 'human' : 'team', question_id: entry.id,
      status: response.status, answers: response.answers,
      body: response.status === 'answered' ? 'Human response received; see answers.' : `Human question ${response.status}; no authorization granted.`,
    });
    if (this.closing || (entry.from !== 'parent' && !active(this.agents.get(entry.from) ?? { status: 'stopped' }))) return;
    try { await this.deliver(reply); this.record('accepted', { message_id: reply.id }); }
    catch (error) { this.record('delivery_failed', { message_id: reply.id, error: String(error.message) }); }
  }
  cancelUserQuestions(who) {
    for (const pending of this.userQuestions.values()) if (!who || pending.from === who) pending.controller.abort();
  }
  async call(who, operation, args = {}, signal) {
    if (this.closing) throw new Error('Team shutting down');
    if (who !== 'parent' && !active(this.agents.get(who) ?? { status: 'stopped' })) throw new Error('Unknown sender');
    switch (operation) {
      case 'agent_list': return this.list();
      case 'agent_wait': return this.wait(who, args, signal);
      case 'agent_send': return this.send(who, args.to, args.message);
      case 'agent_ask': return args.to === 'user'
        ? this.askHuman(who, args)
        : this.send(who, args.to ?? 'parent', args.question, 'question');
      case 'agent_reply': {
        const q = this.records.find(r => r.id === args.question_id && r.kind === 'question');
        if (!q || q.to === 'user' || q.to !== who) throw new Error('Question not found or not addressed to you');
        if (this.records.some(r => r.kind === 'reply' && r.question_id === q.id && !this.records.some(f => f.kind === 'delivery_failed' && f.message_id === r.id))) throw new Error('Question already answered');
        return this.send(who, q.from, args.answer, 'reply', { question_id: q.id });
      }
      case 'board_post': {
        text(args.topic, 'topic', 100); text(args.body);
        if (args.reply_to && !this.records.some(r => r.kind === 'post' && r.id === args.reply_to)) throw new Error('Post not found');
        return this.record('post', { from: who, topic: args.topic, body: args.body, reply_to: args.reply_to });
      }
      case 'board_read': return this.page(this.records.filter(r => r.kind === 'post' && (!args.topic || r.topic === args.topic)), args);
      case 'agent_inbox': return this.page(this.records.filter(r => r.to === who || r.from === who), args);
      case 'agent_stop': {
        if (who !== 'parent') throw new Error('Only parent can stop agents');
        await this.stop(args.agent); return { stopped: args.agent };
      }
      default: throw new Error(`Unknown operation: ${operation}`);
    }
  }
  page(records, args) {
    const index = args.after ? records.findIndex(r => r.id === args.after) : -1;
    if (args.after && index < 0) throw new Error('Cursor not found in this query');
    const limit = Math.max(1, Math.min(50, Number(args.limit) || 10));
    const items = []; let size = 0;
    for (const r of records.slice(index + 1, index + 1 + limit)) {
      let entry = r.body?.length > 12000 ? { ...r, body: r.body.slice(0, 12000), truncated: true } : r;
      if (Buffer.byteLength(JSON.stringify(entry)) > 39000) {
        entry = { id: r.id, time: r.time, kind: r.kind, from: r.from, to: r.to, question_id: r.question_id, status: r.status, origin: r.origin, truncated: true, body: 'Oversized entry; read full event in archive.' };
      }
      const bytes = Buffer.byteLength(JSON.stringify(entry));
      if (size + bytes > 40000 && items.length) break;
      items.push(entry); size += bytes;
    }
    return { items, next: items.at(-1)?.id ?? args.after ?? null, more: index + 1 + items.length < records.length, archive: join(this.directory, 'events.jsonl') };
  }
  async stop(name) {
    const a = this.agents.get(name); if (!a) throw new Error('Unknown agent');
    this.cancelUserQuestions(name);
    this.tokens.delete(a.token); this.change(a, 'stopped');
    if (a.rpc) await a.rpc.stop();
  }
  async close() {
    if (this.closing) return;
    this.closing = true;
    this.notifyWaiters();
    this.cancelUserQuestions();
    await Promise.all([...this.userQuestions.values()].map(p => p.task));
    await this.ready;
    await Promise.all([...this.agents.keys()].map(name => this.stop(name)));
    this.server.closeAllConnections();
    await new Promise(resolve => this.server.close(resolve));
    writeFileSync(join(this.directory, 'team.json'), JSON.stringify(this.list(), null, 2), { mode: 0o600 });
  }
}
