// Local execution with the invoking user's environment and permissions; no OS sandbox.
// The managed launcher pins these executables without replacing the user's PATH.
export function executable(name) {
  const fallback = { bash: 'bash', node: process.execPath, git: 'git' };
  if (!(name in fallback)) throw new Error(`Unknown local executable: ${name}`);
  return process.env[`PI_TOOL_${name.toUpperCase()}`] || fallback[name];
}

export function processPlan({ executable, args, cwd }) {
  return { command: executable, args, options: { cwd, env: { ...process.env } } };
}

export function executionPlan({ command, cwd }) {
  return processPlan({ executable: executable('bash'), args: ['--noprofile', '--norc', '-c', command], cwd });
}
