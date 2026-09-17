import { matchesKey, truncateToWidth, type TuiMouseEvent } from '@earendil-works/pi-tui';
import { NativeTranscript, type NativeSnapshot } from './native-transcript.ts';
import { safeText } from './observation.mjs';

/** Full terminal viewport, with no editor and no worker control capabilities. */
export class TranscriptViewer {
  private transcript: NativeTranscript;
  private offset = 0;
  private maxOffset = 0;
  private pageSize = 1;
  private follow = true;
  private disposed = false;
  private ownsMouse = false;
  constructor(private source: { list(): any; observeNative(name: string): NativeSnapshot },
    private tui: any, private theme: any, private done: (action: 'back' | 'close') => void, private name: string) {
    const agent = source.list().agents.find((a: any) => a.name === name);
    this.transcript = new NativeTranscript(tui, agent?.cwd ?? process.cwd());
    // Fullscreen Pi already owns mouse reporting and dispatches normalized events.
    // Regular Pi does not: temporarily request press/wheel SGR events, then restore.
    if (tui.mode === 'regular' && tui.terminal.write) {
      this.ownsMouse = true;
      tui.terminal.write('\x1b[?1000h\x1b[?1006h');
    }
  }
  dispose() {
    if (this.disposed) return;
    this.disposed = true;
    if (this.ownsMouse) this.tui.terminal.write('\x1b[?1000l\x1b[?1006l');
  }
  invalidate() { this.transcript.invalidate(); }
  private scroll(step: number) {
    this.follow = false;
    this.offset = Math.max(0, Math.min(this.maxOffset, this.offset + step));
    this.tui.requestRender();
  }
  handleMouse(event: TuiMouseEvent) {
    if (event.type === 'wheel') { this.scroll(event.wheelDelta ?? 0); return { handled: true, render: true }; }
    return { handled: true }; // Never route clicks to the parent's transcript/editor.
  }
  handleInput(data: string) {
    const mouse = /^\x1b\[<(\d+);\d+;\d+([Mm])$/.exec(data);
    if (mouse) {
      const button = Number(mouse[1]);
      if (mouse[2] === 'M' && (button & 64) && (button & 3) < 2) this.scroll((button & 1) ? 3 : -3);
      return;
    }
    if (matchesKey(data, 'escape')) { this.done('back'); return; }
    if (data === 'q' || matchesKey(data, 'ctrl+c') || matchesKey(data, 'ctrl+shift+t')) { this.done('close'); return; }
    if (matchesKey(data, 'ctrl+o')) this.transcript.toggleExpanded();
    else if (matchesKey(data, 'ctrl+t')) this.transcript.toggleThinking();
    else if (matchesKey(data, 'home') || data === 'g') { this.offset = 0; this.follow = false; }
    else if (matchesKey(data, 'end') || data === 'f' || data === 'G') this.follow = true;
    else {
      const step = matchesKey(data, 'up') || data === 'k' ? -1 : matchesKey(data, 'down') || data === 'j' ? 1
        : matchesKey(data, 'pageUp') ? -this.pageSize : matchesKey(data, 'pageDown') ? this.pageSize : 0;
      if (step) { this.scroll(step); return; }
    }
    this.tui.requestRender();
  }
  render(width: number): string[] {
    const height = Math.max(1, this.tui.terminal.rows || 24);
    this.pageSize = Math.max(1, height - 3);
    const agent = this.source.list().agents.find((a: any) => a.name === this.name);
    this.transcript.update(this.source.observeNative(this.name));
    const lines = this.transcript.render(Math.max(1, width));
    this.maxOffset = Math.max(0, lines.length - this.pageSize);
    this.offset = this.follow ? this.maxOffset : Math.min(this.offset, this.maxOffset);
    const body = lines.slice(this.offset, this.offset + this.pageSize);
    while (body.length < this.pageSize) body.push('');
    const title = safeText(`${this.name} · READ ONLY · ${agent?.status ?? 'unavailable'} · ${this.follow ? 'FOLLOW' : 'SCROLL'} · ${this.offset + 1}/${lines.length}`).replace(/[\n\t]/g, ' ');
    return [this.theme.fg('accent', title), '─'.repeat(Math.max(0, width)), ...body,
      this.theme.fg('dim', 'Wheel/↑↓/PgUp/PgDn scroll · End follow · Ctrl+O tools · Ctrl+T thinking · Esc back · q close')]
      .slice(0, height).map(line => truncateToWidth(line, Math.max(0, width), '', true));
  }
}
