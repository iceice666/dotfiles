import type { Theme } from "@earendil-works/pi-coding-agent";
import { matchesKey, truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";
import { stripVTControlCharacters } from "node:util";
import type { TaskManager } from "./manager";

// Never allow process output to issue terminal commands (including OSC sequences).
const clean = (s: string) => stripVTControlCharacters(s).replace(/\r\n?/g, "\n").replace(/\t/g, "    ").replace(/[\x00-\x08\x0b-\x1f\x7f-\x9f]/g, "");
const single = (s: string) => clean(s).replace(/\s+/g, " ");

export class BackgroundPanel {
  private selected?: string;
  private frozen?: string[];
  private end = 0;
  private pageSize = 10;
  private timer?: ReturnType<typeof setInterval>;
  private disposed = false;

  constructor(
    private manager: Pick<TaskManager, "list" | "output">,
    private theme: Theme,
    private height: () => number,
    private requestRender: () => void,
    private onClose: () => void,
    private cancelKey: (data: string) => boolean,
  ) {
    this.timer = setInterval(() => { if (!this.disposed) this.requestRender(); }, 250);
  }

  close(): void { this.dispose(); this.onClose(); }
  dispose(): void {
    this.disposed = true;
    clearInterval(this.timer);
    this.timer = undefined;
  }
  invalidate(): void {} // Theme and live state are evaluated on every render.

  private tasks() {
    const tasks = this.manager.list();
    if (!tasks.some(t => t.id === this.selected)) {
      this.selected = tasks.find(t => t.status === "running" || t.status === "stopping")?.id ?? tasks.at(-1)?.id;
      this.frozen = undefined;
    }
    return tasks;
  }
  private output(): string[] {
    return this.selected ? clean(this.manager.output(this.selected, 2000)).split("\n") : [];
  }

  handleInput(data: string): void {
    if (this.disposed) return;
    if (this.cancelKey(data) || data === "q" || matchesKey(data, "ctrl+shift+b")) { this.close(); return; }
    const tasks = this.tasks();
    const index = tasks.findIndex(t => t.id === this.selected);
    if (matchesKey(data, "up") || matchesKey(data, "down")) {
      const next = Math.max(0, Math.min(tasks.length - 1, index + (matchesKey(data, "up") ? -1 : 1)));
      this.selected = tasks[next]?.id;
      this.frozen = undefined;
    } else if (matchesKey(data, "end") || data === "f") {
      this.frozen = undefined;
    } else if (matchesKey(data, "pageUp") || matchesKey(data, "pageDown") || matchesKey(data, "home") || data === " ") {
      const wasFrozen = !!this.frozen;
      if (!this.frozen) { this.frozen = this.output(); this.end = this.frozen.length; }
      if (data === " " && wasFrozen) this.frozen = undefined;
      else if (matchesKey(data, "home")) this.end = Math.min(this.pageSize, this.frozen.length);
      else if (matchesKey(data, "pageUp")) this.end = Math.max(Math.min(this.pageSize, this.frozen.length), this.end - this.pageSize);
      else if (matchesKey(data, "pageDown")) this.end = Math.min(this.frozen.length, this.end + this.pageSize);
    }
    this.requestRender();
  }

  render(width: number): string[] {
    const height = Math.max(1, Math.floor(this.height()));
    if (width < 4 || height < 12) return [truncateToWidth("BG: enlarge terminal · Esc close", Math.max(0, width))];
    const tasks = this.tasks();
    const index = tasks.findIndex(t => t.id === this.selected);
    const task = tasks[index];
    const listSize = Math.min(tasks.length, 5, Math.max(1, height - 13));
    const start = Math.max(0, Math.min(index - Math.floor(listSize / 2), tasks.length - listSize));
    const lines = [this.theme.fg("accent", this.theme.bold(`Background tasks · ${tasks.length} · ${this.frozen ? "PAUSED snapshot" : "LIVE 250ms"}`))];
    for (const t of tasks.slice(start, start + listSize)) {
      const label = `${t.id === this.selected ? "▸" : " "} ${t.id.slice(0, 8)} ${t.status} · ${single(t.command)}`;
      lines.push(this.theme.fg(t.id === this.selected ? "accent" : "muted", label));
    }
    if (task) {
      const seconds = Math.max(0, Math.floor(((task.endedAt ? Date.parse(task.endedAt) : Date.now()) - Date.parse(task.startedAt)) / 1000));
      lines.push(`Task ${index + 1}/${tasks.length} · PID ${task.pid ?? "—"} · ${seconds}s · ${task.status}${task.exitCode != null ? ` · exit ${task.exitCode}` : ""}${task.signal ? ` · ${task.signal}` : ""}`);
      lines.push(`$ ${single(task.command)}`, `cwd: ${single(task.cwd)}`, `Log: ${single(task.logPath)} (max 10 MiB)`);
      if (task.error) lines.push(this.theme.fg("error", single(task.error)));
    } else lines.push("No background tasks. Start one with /bg start <command>.");
    lines.push(this.theme.fg("dim", "─ Output · stdout + stderr · retained tail, last 2000 lines ─"));
    this.pageSize = Math.max(1, height - lines.length - 4);
    const output = this.frozen ?? this.output();
    const end = this.frozen ? this.end : output.length;
    lines.push(...output.slice(Math.max(0, end - this.pageSize), end));
    while (lines.length < height - 4) lines.push("");
    lines.push(this.theme.fg("dim", "↑↓ task · PgUp/PgDn scroll snapshot · Home oldest · End/f live"));
    lines.push(this.theme.fg("dim", "Space pause/live · Esc/q close (tasks keep running)"));
    const inner = width - 2;
    const row = (s: string) => {
      const text = truncateToWidth(s, inner);
      return `│${text}${" ".repeat(Math.max(0, inner - visibleWidth(text)))}│`;
    };
    return [`╭${"─".repeat(inner)}╮`, ...lines.map(row), `╰${"─".repeat(inner)}╯`];
  }
}
