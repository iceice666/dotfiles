import {
  AssistantMessageComponent, UserMessageComponent, ToolExecutionComponent,
  createReadToolDefinition, createBashToolDefinition, createEditToolDefinition,
  createWriteToolDefinition, createGrepToolDefinition, createFindToolDefinition,
  createLsToolDefinition, createPowerShellToolDefinition,
} from '@earendil-works/pi-coding-agent';
import { Text, type Component } from '@earendil-works/pi-tui';
import { safeText } from './observation.mjs';

export type NativeSnapshot = { revision: number; truncated: boolean; messages: Array<{
  id: string; message: any; streaming: boolean; tool?: { args: any; status: string };
}> };

// Sanitize data, not rendered ANSI. Never pass an execute function to the viewer.
function clean(value: any, depth = 0): any {
  if (depth > 64) return '[Nested data omitted]';
  if (typeof value === 'string') return safeText(value).replace(/\t/g, '    ');
  if (Array.isArray(value)) return value.map(item => clean(item, depth + 1));
  if (value && typeof value === 'object') {
    if (value.type === 'image') return { type: 'text', text: '[Image]' };
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [safeText(k), clean(v, depth + 1)]));
  }
  return value;
}
const factories = [createReadToolDefinition, createBashToolDefinition, createEditToolDefinition,
  createWriteToolDefinition, createGrepToolDefinition, createFindToolDefinition,
  createLsToolDefinition, createPowerShellToolDefinition];

/** Display adapter only: no session, editor, RPC client, or tool execution capability. */
export class NativeTranscript {
  private components: Component[] = [];
  private expanded = false;
  private hideThinking = false;
  private revision = -1;
  private snapshot?: NativeSnapshot;
  private renderers = new Map<string, any>();
  private width = -1;
  private cached?: string[];
  constructor(private tui: any, private cwd: string) {
    for (const factory of factories) {
      const { name, renderCall, renderResult, renderShell } = factory(cwd);
      // Edit's normal pre-execution preview reads today's file. A historical viewer
      // must use the recorded diff, never recompute it against changed files.
      this.renderers.set(name, { renderShell, renderResult, renderCall: name === 'edit' && renderCall
        ? (args: any, theme: any, context: any) => renderCall(args, theme, { ...context, argsComplete: false })
        : renderCall });
    }
  }
  invalidate() {
    this.cached = undefined;
    for (const component of this.components) component.invalidate();
  }
  toggleExpanded() { this.expanded = !this.expanded; this.revision = -1; this.cached = undefined; }
  toggleThinking() { this.hideThinking = !this.hideThinking; this.revision = -1; this.cached = undefined; }
  update(snapshot: NativeSnapshot) {
    this.snapshot = snapshot;
    if (this.revision === snapshot.revision) return;
    this.revision = snapshot.revision;
    this.cached = undefined;
    this.components = [];
    const tools = new Map<string, ToolExecutionComponent>();
    const renderUI = { requestRender: () => { this.cached = undefined; this.tui.requestRender(); } } as any;
    const tool = (id: string, name: string, args: any) => {
      let component = tools.get(id);
      if (!component) {
        component = new ToolExecutionComponent(name, id, args ?? {}, { showImages: false }, this.renderers.get(name) ?? {
          renderCall: (args: any, theme: any) => new Text(theme.fg('toolTitle', theme.bold(name)) + '\n' + JSON.stringify(args), 0, 0),
        }, renderUI, this.cwd);
        component.setExpanded(this.expanded);
        tools.set(id, component); this.components.push(component);
      } else if (args && Object.keys(args).length) component.updateArgs(args);
      return component;
    };
    if (snapshot.truncated) this.components.push(new Text('Earlier observation truncated; see the agent session file for full history.', 1, 1));
    for (const record of snapshot.messages) {
      const message = clean(record.message);
      if (message.role === 'user') {
        const text = typeof message.content === 'string' ? message.content : (message.content ?? [])
          .map((c: any) => c.type === 'text' ? c.text : c.type === 'image' ? '[Image]' : '').join('\n');
        this.components.push(new UserMessageComponent(text));
      } else if (message.role === 'assistant') {
        // Native assistant component handles Markdown, fenced code, thinking/errors.
        // Split at tool calls to preserve the actual text/tool timeline.
        let segment: any[] = [];
        const flush = (last = false) => {
          if (!segment.length && !(last && message.errorMessage)) return;
          const part = { ...message, content: segment, ...(last ? {} : { stopReason: 'toolUse', errorMessage: undefined }) };
          const component = new AssistantMessageComponent(part, this.hideThinking);
          component.updateContent(part, record.streaming);
          this.components.push(component); segment = [];
        };
        for (const block of message.content ?? []) {
          if (block.type !== 'toolCall') { segment.push(block); continue; }
          flush();
          const component = tool(block.id, block.name, block.arguments);
          if (!record.streaming) component.setArgsComplete();
        }
        flush(true);
      } else if (message.role === 'toolResult') {
        const component = tool(message.toolCallId ?? record.id, message.toolName ?? 'tool', clean(record.tool?.args));
        component.markExecutionStarted(); component.setArgsComplete();
        component.updateResult({ content: message.content ?? [], details: message.details, isError: Boolean(message.isError) }, record.streaming);
      } else if (message.content) {
        // Unknown custom types cannot transport executable child extension renderers.
        this.components.push(new Text(`[${message.role}]\n${typeof message.content === 'string' ? message.content : JSON.stringify(message.content)}`, 1, 1));
      }
    }
    if (!this.components.length) this.components.push(new Text('Waiting for transcript events…', 1, 1));
  }
  render(width: number): string[] {
    // Key toggles rebuild once, even when no new worker event has arrived.
    if (this.snapshot && this.revision < 0) this.update(this.snapshot);
    if (width < 4) return [''];
    if (!this.cached || this.width !== width) {
      this.width = width;
      this.cached = this.components.flatMap(component => component.render(width));
    }
    return this.cached;
  }
}
