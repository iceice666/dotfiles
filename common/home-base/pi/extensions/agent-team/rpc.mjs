import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';

// Strict LF framing. setEncoding handles UTF-8 split across chunks.
export class RpcProcess {
  constructor(command, args, options, onEvent = () => {}) {
    this.pending = new Map();
    this.stderr = '';
    this.closed = false;
    this.child = spawn(command, args, { ...options, stdio: ['pipe', 'pipe', 'pipe'], detached: process.platform !== 'win32' });
    this.child.stdout.setEncoding('utf8');
    this.child.stderr.setEncoding('utf8');
    let buffer = '';
    this.child.stdout.on('data', chunk => {
      buffer += chunk;
      if (buffer.length > 16 * 1024 * 1024) { this.fail(new Error('RPC frame too large')); void this.stop(); return; }
      let end;
      while ((end = buffer.indexOf('\n')) >= 0) {
        const line = buffer.slice(0, end).replace(/\r$/, '');
        buffer = buffer.slice(end + 1);
        if (!line) continue;
        let event;
        try { event = JSON.parse(line); }
        catch { this.fail(new Error('Invalid RPC JSON')); void this.stop(); return; }
        if (event.type === 'response') {
          const pending = this.pending.get(event.id);
          if (pending) {
            clearTimeout(pending.timer); this.pending.delete(event.id);
            event.success ? pending.resolve(event.data) : pending.reject(new Error(event.error || 'RPC failed'));
          }
        } else if (event.type === 'extension_ui_request' && ['confirm', 'select', 'input', 'editor'].includes(event.method)) {
          // Never auto-approve a child permission prompt, and never leave it hanging.
          this.write({ type: 'extension_ui_response', id: event.id, cancelled: true });
          onEvent({ type: 'team_dialog_cancelled', title: event.title });
        } else onEvent(event);
      }
    });
    this.child.stderr.on('data', chunk => { this.stderr = (this.stderr + chunk).slice(-8192); });
    this.child.stdin.on('error', error => this.fail(error));
    this.child.on('error', error => this.fail(error));
    this.exited = new Promise(resolve => this.child.once('close', (code, signal) => {
      this.closed = true;
      this.fail(new Error(`Pi exited (${code ?? signal}): ${this.stderr}`));
      onEvent({ type: 'team_exit', code, signal, stderr: this.stderr });
      resolve();
    }));
  }
  fail(error) {
    for (const p of this.pending.values()) { clearTimeout(p.timer); p.reject(error); }
    this.pending.clear();
  }
  write(value) {
    if (this.closed || this.child.stdin.destroyed) throw new Error('Pi process is closed');
    this.child.stdin.write(JSON.stringify(value) + '\n');
  }
  request(type, data = {}, timeout = 30000) {
    const id = randomUUID();
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { this.pending.delete(id); reject(new Error(`RPC ${type} timed out`)); }, timeout);
      this.pending.set(id, { resolve, reject, timer });
      try { this.write({ ...data, type, id }); }
      catch (e) { clearTimeout(timer); this.pending.delete(id); reject(e); }
    });
  }
  async stop() {
    if (this.stopping) return this.stopping;
    this.stopping = (async () => {
      const kill = signal => {
        if (!this.child.pid) return;
        try {
          if (process.platform !== 'win32') process.kill(-this.child.pid, signal);
          else this.child.kill(signal);
        } catch (e) { if (e.code !== 'ESRCH') throw e; }
      };
      kill('SIGTERM');
      const timer = setTimeout(() => kill('SIGKILL'), 1500);
      await this.exited;
      clearTimeout(timer);
      // Pi may have exited before a descendant that ignored SIGTERM.
      kill('SIGKILL');
    })();
    return this.stopping;
  }
}
