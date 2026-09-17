// Passive, bounded projection of the JSON RPC stream for Pi's native renderers.
// No transport access: message_end snapshots win over locally assembled deltas.
export const NATIVE_OBSERVATION_LIMIT = 1024 * 1024;
export const NATIVE_OBSERVATION_MESSAGES = 500;
const copy = value => structuredClone(value);
const size = value => Buffer.byteLength(JSON.stringify(value));
const MARKER = '[Native observation truncated; full history is in the agent sessionFile.]';

// Complete the common incomplete JSON prefixes emitted while streaming tool args.
// The final toolcall_end (or message_end) always replaces this preview.
function partialArguments(text) {
  try { return JSON.parse(text); } catch { /* incomplete */ }
  const stack = []; let quoted = false, escaped = false;
  for (const c of text) {
    if (quoted) {
      if (escaped) escaped = false;
      else if (c === '\\') escaped = true;
      else if (c === '"') quoted = false;
    } else if (c === '"') quoted = true;
    else if (c === '{') stack.push('}');
    else if (c === '[') stack.push(']');
    else if (c === '}' || c === ']') stack.pop();
  }
  let candidate = text;
  if (quoted) candidate = (escaped ? candidate.slice(0, -1) : candidate) + '"';
  candidate = candidate.replace(/,\s*$/, '').replace(/:\s*$/, ':null');
  try { return JSON.parse(candidate + stack.reverse().join('')); } catch { return {}; }
}

export class NativeObservation {
  constructor(limit = NATIVE_OBSERVATION_LIMIT, maxMessages = NATIVE_OBSERVATION_MESSAGES) {
    this.limit = Math.max(512, limit); this.maxMessages = Math.max(1, maxMessages);
    this.messages = []; this.current = null; this.nextId = 0;
    this.revision = 0; this.truncated = false;
  }
  add(message, streaming = true) {
    const entry = { id: String(++this.nextId), message: copy(message), streaming };
    this.messages.push(entry); return entry;
  }
  tool(id, name) {
    let entry = this.messages.find(e => e.message.role === 'toolResult' && e.message.toolCallId === id);
    if (!entry) entry = this.add({ role: 'toolResult', toolCallId: id, toolName: name ?? 'tool', content: [], isError: false, timestamp: Date.now() });
    entry.tool ??= { args: {}, status: 'running' };
    return entry;
  }
  ingest(event) {
    if (!event || typeof event.type !== 'string') return false;
    const { type, message } = event;
    if (['message_start', 'message_end', 'message_update'].includes(type) && message) {
      let entry;
      if (message.role === 'toolResult') entry = this.tool(message.toolCallId, message.toolName);
      else {
        if (type === 'message_start' || !this.current || this.current.message.role !== message.role) this.current = this.add(message);
        entry = this.current;
      }
      entry.message = copy(message); entry.streaming = type !== 'message_end';
      delete entry._arguments;
      if (entry.tool && type === 'message_end') { entry.tool.status = 'completed'; entry.tool.authoritative = true; }
      if (type === 'message_end' && this.current === entry) this.current = null;
    } else if (type === 'message_update') {
      const delta = event.assistantMessageEvent;
      const index = delta?.contentIndex;
      if (!Number.isInteger(index) || index < 0 || index > 1023) return false;
      if (!/^(text|thinking|toolcall)_(start|delta|end)$/.test(delta.type)) return false;
      if (!this.current || this.current.message.role !== 'assistant') this.current = this.add({ role: 'assistant', content: [], timestamp: Date.now() });
      const entry = this.current, content = entry.message.content;
      if (event.usage) entry.message.usage = copy(event.usage);
      // Fill gaps rather than exposing sparse/null content blocks to native components.
      while (content.length <= index) content.push({ type: 'text', text: '' });
      if (delta.type.startsWith('toolcall')) {
        if (delta.type === 'toolcall_start') {
          content[index] = { type: 'toolCall', id: delta.id ?? '', name: delta.toolName ?? 'tool', arguments: {} };
          (entry._arguments ??= {})[index] = '';
        } else if (delta.type === 'toolcall_delta') {
          if (content[index].type !== 'toolCall') content[index] = { type: 'toolCall', id: '', name: 'tool', arguments: {} };
          const buffers = entry._arguments ??= {};
          buffers[index] = (buffers[index] ?? '') + (delta.delta ?? '');
          content[index].arguments = partialArguments(buffers[index]);
        } else {
          content[index] = copy(delta.toolCall ?? content[index]);
          if (entry._arguments) delete entry._arguments[index];
        }
      } else {
        const kind = delta.type.startsWith('thinking') ? 'thinking' : 'text';
        if (content[index].type !== kind || delta.type.endsWith('_start')) content[index] = { type: kind, [kind]: '' };
        if (delta.type.endsWith('_delta')) content[index][kind] += delta.delta ?? '';
        else if (delta.type.endsWith('_end')) content[index][kind] = delta.content ?? content[index][kind];
      }
    } else if (['tool_execution_start', 'tool_execution_update', 'tool_execution_end'].includes(type)) {
      const entry = this.tool(event.toolCallId, event.toolName);
      if (entry.tool.authoritative) return false;
      if (event.args !== undefined) entry.tool.args = copy(event.args);
      const result = type === 'tool_execution_end' ? event.result : event.partialResult;
      if (result) entry.message = { ...entry.message, ...copy(result), role: 'toolResult', toolCallId: event.toolCallId, toolName: event.toolName ?? entry.message.toolName };
      if (type === 'tool_execution_end') {
        entry.message.isError = !!event.isError; entry.streaming = false; entry.tool.status = 'completed';
      }
    } else return false;
    this.bound(); this.revision++; return true;
  }
  bound() {
    // Include private JSON argument buffers in the budget; never retain evicted
    // entries through a separate ID map or the current-message pointer.
    while (this.messages.length > 1 && (this.messages.length > this.maxMessages || size(this.messages) > this.limit - 128)) {
      const removed = this.messages.shift();
      if (removed === this.current) this.current = null;
      this.truncated = true;
    }
    if (size(this.messages) > this.limit - 128) {
      const entry = this.messages[0];
      const role = ['assistant', 'user', 'toolResult'].includes(entry.message.role) ? entry.message.role : 'user';
      const previous = entry.message;
      entry.message = { role, content: [{ type: 'text', text: MARKER }], timestamp: 0 };
      if (role === 'toolResult') {
        // Retain ordinary call identity so later final results still deduplicate.
        entry.message.toolCallId = String(previous.toolCallId ?? '').slice(0, 64);
        entry.message.toolName = String(previous.toolName ?? 'tool').slice(0, 32);
        entry.message.isError = !!previous.isError;
      }
      delete entry._arguments; delete entry.tool;
      // Untrusted identifiers may themselves exceed the budget once JSON-escaped.
      if (size(this.messages) > this.limit - 128) entry.message = { role: 'user', content: MARKER, timestamp: 0 };
      this.truncated = true;
    }
  }
  snapshot() {
    return { messages: this.messages.map(({ _arguments, ...entry }) => copy(entry)), revision: this.revision, truncated: this.truncated };
  }
}
