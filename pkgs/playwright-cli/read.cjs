#!/usr/bin/env node
const { spawnSync } = require('node:child_process');
const path = require('node:path');
const { extractionExpression, parseResult } = require('./extract.cjs');

try {
  const args = process.argv.slice(2);
  if (args.includes('--help')) {
    console.log('Usage: playwright-read --session NAME [--max-chars 24000]\nRead the existing session tab as bounded, untrusted Markdown. Does not navigate or close it.');
    process.exit(0);
  }
  let session;
  let maxChars = 24000;
  while (args.length) {
    const arg = args.shift();
    if (arg === '--session') session = args.shift();
    else if (arg === '--max-chars') maxChars = Number(args.shift());
    else throw new Error(`Unknown argument: ${arg}`);
  }
  if (!session || !/^[a-zA-Z0-9_-]{1,80}$/.test(session)) {
    throw new Error('An explicit --session NAME is required (1–80 letters, digits, underscores or hyphens)');
  }
  const result = spawnSync(process.execPath, [
    path.join(__dirname, 'cli.cjs'), `-s=${session}`, 'eval', extractionExpression(maxChars),
  ], { encoding: 'utf8', timeout: 60000, maxBuffer: 4 * 1024 * 1024 });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`Playwright extraction failed (exit ${result.status}); inspect the session with playwright-cli`);
  console.log(JSON.stringify(parseResult(result.stdout), null, 2));
} catch (error) {
  console.error(`playwright-read: ${error.message}`);
  process.exitCode = 1;
}
