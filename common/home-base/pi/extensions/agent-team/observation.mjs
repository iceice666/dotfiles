import { stripVTControlCharacters } from 'node:util';
import { createHash } from 'node:crypto';

// Passive projection of RPC events. Never queries or writes to the child process.
export const OBSERVATION_LIMIT = 256 * 1024;
const MARKER = '[Observation truncated; full history is in the agent sessionFile.]\n';
export function safeText(value) {
  return stripVTControlCharacters(String(value ?? '')).replace(/\r\n?/g, '\n').replace(/[\u0000-\u0008\u000b-\u001f\u007f-\u009f\u202a-\u202e\u2066-\u2069]/g, '');
}
const json = value => safeText(JSON.stringify(value ?? {}));
const tail = (value, bytes) => {
  const buffer = Buffer.from(value);
  let start = Math.max(0, buffer.length - bytes);
  while (start < buffer.length && (buffer[start] & 0xc0) === 0x80) start++;
  return buffer.subarray(start).toString();
};
function contentParts(content) {
  if (typeof content === 'string') return [safeText(content)];
  return (content ?? []).map(c => {
    if (c.type === 'text') return safeText(c.text);
    if (c.type === 'thinking') return `[Thinking]\n${safeText(c.thinking)}`;
    if (c.type === 'toolCall') return `[Tool call: ${safeText(c.name)}]\n${json(c.arguments)}`;
    if (c.type === 'image') return '[Image]';
    return `[${safeText(c.type ?? 'content')}]`;
  });
}
export class Observation {
  constructor(limit = OBSERVATION_LIMIT) {
    this.limit = Math.max(256, limit); this.entries = []; this.current = null;
    this.revision = 0; this.truncated = false;
  }
  add(role, key) {
    const entry = { role: safeText(role), key, parts: new Map() };
    this.entries.push(entry); return entry;
  }
  setContent(entry, content) {
    let parts = contentParts(content);
    if (parts.length > 1024) { parts = parts.slice(-1024); this.truncated = true; }
    entry.parts = new Map(parts.map((part, index) => [index, part]));
  }
  tool(id, name) {
    const key = createHash('sha256').update(String(id ?? '')).digest('hex');
    return this.entries.find(e => e.key === key && e.role.startsWith('Tool result')) ?? this.add(`Tool result: ${safeText(name ?? 'tool')}`, key);
  }
  ingest(event) {
    const { type, message } = event;
    if (type === 'message_start' || type === 'message_end' || (type === 'message_update' && message)) {
      if (!message) return false;
      let entry;
      if (message.role === 'toolResult') entry = this.tool(message.toolCallId, message.toolName);
      else {
        if (type === 'message_start' || !this.current || this.current.role !== message.role) this.current = this.add(message.role);
        entry = this.current;
      }
      this.setContent(entry, message.content);
      if (message.isError || message.errorMessage) entry.parts.set(-1, `[Error] ${safeText(message.errorMessage ?? 'Tool failed')}`);
      if (type === 'message_end' && entry === this.current) this.current = null;
    } else if (type === 'message_update') {
      const delta = event.assistantMessageEvent;
      if (!delta || !Number.isInteger(delta.contentIndex) || delta.contentIndex < 0) return false;
      if (!this.current) this.current = this.add('assistant');
      const parts = this.current.parts, index = delta.contentIndex;
      if (delta.type === 'text_start') parts.set(index, '');
      else if (delta.type === 'thinking_start') parts.set(index, '[Thinking]\n');
      else if (delta.type === 'toolcall_start') parts.set(index, `[Tool call: ${safeText(delta.toolName)}]\n`);
      else if (delta.type.endsWith('_delta')) parts.set(index, (parts.get(index) ?? '') + safeText(delta.delta));
      else if (delta.type === 'text_end') parts.set(index, safeText(delta.content));
      else if (delta.type === 'thinking_end') parts.set(index, `[Thinking]\n${safeText(delta.content)}`);
      else if (delta.type === 'toolcall_end') parts.set(index, contentParts([delta.toolCall ?? { type: 'toolCall' }])[0]);
      else return false;
    } else if (type.startsWith('tool_execution_')) {
      const entry = this.tool(event.toolCallId, event.toolName);
      if (type === 'tool_execution_start') this.setContent(entry, '[Running]');
      else if (type === 'tool_execution_update') this.setContent(entry, event.partialResult?.content);
      else if (type === 'tool_execution_end') {
        this.setContent(entry, event.result?.content);
        if (event.isError) entry.parts.set(-1, '[Error] Tool failed');
      } else return false;
    } else return false;
    this.bound(); this.revision++; return true;
  }
  renderEntry(entry) { return `[${entry.role}]\n${[...entry.parts.values()].join('\n')}`; }
  bound() {
    const budget = this.limit - Buffer.byteLength(MARKER);
    let size = this.entries.reduce((sum, entry) => sum + Buffer.byteLength(this.renderEntry(entry)) + 2, 0);
    while (this.entries.length > 1 && (size > budget || this.entries.length > 1024)) {
      const removed = this.entries.shift();
      size -= Buffer.byteLength(this.renderEntry(removed)) + 2;
      if (removed === this.current) this.current = null;
      this.truncated = true;
    }
    const entry = this.entries[0];
    if (!entry) return;
    while (entry.parts.size > 1 && (size > budget || entry.parts.size > 1024)) {
      const key = entry.parts.keys().next().value;
      const part = entry.parts.get(key); entry.parts.delete(key);
      size -= Buffer.byteLength(part) + 1; this.truncated = true;
    }
    if (size > budget) {
      const key = entry.parts.keys().next().value ?? 0;
      // Role names are RPC data too; bound them independently.
      entry.role = tail(entry.role, Math.min(128, Math.floor(budget / 4)));
      const overhead = Buffer.byteLength(`[${entry.role}]\n`) + 2;
      entry.parts.set(key, tail(entry.parts.get(key) ?? '', Math.max(0, budget - overhead)));
      this.truncated = true;
    }
  }
  snapshot() {
    return { text: (this.truncated ? MARKER : '') + this.entries.map(entry => this.renderEntry(entry)).join('\n\n'), revision: this.revision };
  }
}
