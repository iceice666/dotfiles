import { matchesKey, truncateToWidth } from '@earendil-works/pi-tui';
import { safeText } from './observation.mjs';

/** Agent picker only. Transcript is mounted separately by the controller. */
export class TeamPanel {
  private selected = 0;
  constructor(private source: { list(): any }, private tui: any, private theme: any,
    private done: (name?: string) => void, selectedName?: string) {
    this.selected = Math.max(0, source.list().agents.findIndex((a: any) => a.name === selectedName));
  }
  invalidate() {}
  handleInput(data: string) {
    if (matchesKey(data, 'escape') || matchesKey(data, 'ctrl+c') || matchesKey(data, 'ctrl+shift+t') || data === 'q') { this.done(); return; }
    const agents = this.source.list().agents;
    if (matchesKey(data, 'up')) this.selected = Math.max(0, this.selected - 1);
    if (matchesKey(data, 'down')) this.selected = Math.min(agents.length - 1, this.selected + 1);
    if (matchesKey(data, 'enter') && agents[this.selected]) { this.done(agents[this.selected].name); return; }
    this.tui.requestRender();
  }
  render(width: number): string[] {
    const agents = this.source.list().agents;
    this.selected = Math.max(0, Math.min(this.selected, agents.length - 1));
    const capacity = Math.max(1, Math.floor((this.tui.terminal.rows || 24) * .7) - 4);
    const start = Math.max(0, this.selected - capacity + 1);
    const rows = agents.length ? agents.slice(start, start + capacity).map((a: any, i: number) => {
      const text = safeText(`${i + start === this.selected ? '›' : ' '} ${a.name} | ${a.status} | PID ${a.pid ?? '—'} | ${a.activity ?? ''}`).replace(/[\n\t]/g, ' ');
      return i + start === this.selected ? this.theme.fg('accent', text) : text;
    }) : ['No team yet. Ask the coordinator to spawn a teammate.'];
    return ['─'.repeat(Math.max(0, width)), this.theme.fg('accent', 'Agent team · Select an agent'), ...rows,
      '↑↓ select · Enter fullscreen transcript · Esc/q close']
      .map(s => truncateToWidth(s, Math.max(0, width), ''));
  }
}
