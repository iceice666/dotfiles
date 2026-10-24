import assert from 'node:assert/strict';
import dns from 'node:dns';
import { execFileSync } from 'node:child_process';
import tls from 'node:tls';
import { test } from 'node:test';
import { brotliCompressSync, brotliDecompressSync } from 'node:zlib';

// Run directly with each managed runtime: node scripts/tests/test-nodejs-security.mjs [22|24].
const minimumNode = { 22: '22.23.4', 24: '24.22.1' };
const major = process.versions.node.split('.')[0];
const expectedMajor = process.argv[2];

function atLeast(actual, minimum) {
  assert.equal(typeof actual, 'string', `missing runtime dependency version (expected ${minimum})`);
  const actualParts = actual.split('.').map(Number);
  const minimumParts = minimum.split('.').map(Number);
  assert.ok(actualParts.every(Number.isInteger), `unrecognized version: ${actual}`);
  const difference = minimumParts.map((part, index) => actualParts[index] - part).find(value => value !== 0);
  assert.ok(difference === undefined || difference > 0, `${actual} must be >= ${minimum}`);
}

test('runtime uses a supported fixed Node branch', () => {
  if (expectedMajor !== undefined) {
    assert.ok(Object.hasOwn(minimumNode, expectedMajor), 'expected branch must be 22 or 24');
    assert.equal(major, expectedMajor);
  }
  assert.ok(Object.hasOwn(minimumNode, major), `unsupported Node major ${major}`);
  assert.ok(!process.version.includes('-'), 'a prerelease is not security-release evidence');
  atLeast(process.versions.node, minimumNode[major]);
});

test('process.execPath remains executable after binary relocation', () => {
  assert.equal(execFileSync(process.execPath, ['-p', 'process.version'], { encoding: 'utf8' }).trim(), process.version);
});

test('runtime includes the fixed bundled dependency versions', () => {
  atLeast(process.versions.openssl, '3.5.9');
  atLeast(process.versions.ares, '1.34.9');
  // Official 22.23.4 bundles Brotli 1.1.0; 24.22.1 bundles 1.2.0.
  atLeast(process.versions.brotli, major === '22' ? '1.1.0' : '1.2.0');
  atLeast(process.versions.sqlite, '3.53.4');
});

test('DNS rejects embedded NUL before lookup, without network access', () => {
  assert.throws(() => dns.lookup('127.0.0.1\0.example.invalid', () => {
    assert.fail('invalid hostname must not reach a lookup callback');
  }), { code: 'ERR_INVALID_ARG_VALUE' });
  const resolver = new dns.Resolver();
  assert.throws(() => resolver.setLocalAddress('127.0.0.1\0'), {
    code: 'ERR_INVALID_ARG_VALUE',
  });
});

test('bundled Brotli roundtrips binary data', () => {
  const input = Buffer.concat([Buffer.from('security regression\0'.repeat(256)), Buffer.from([0, 255, 128])]);
  assert.deepEqual(brotliDecompressSync(brotliCompressSync(input)), input);
});

test('TLS identity checks reject noncanonical IP normalization', () => {
  // Adapted from upstream test/parallel/test-tls-check-server-identity.js.
  const cases = [
    ['0127.0.0.1', '87.0.0.1'],
    ['0177.0.0.1', '127.0.0.1'],
    ['0x7f.0.0.1', '127.0.0.1'],
    ['2130706433', '127.0.0.1'],
    ['127.1', '127.0.0.1'],
    ['\uFF11\uFF12\uFF17.0.0.1', '127.0.0.1'],
    ['127\u30020.0.1', '127.0.0.1'],
  ];
  for (const [host, normalized] of cases) {
    const error = tls.checkServerIdentity(host, {
      subjectaltname: `DNS:${normalized}`,
      subject: {},
    });
    assert.equal(error?.code, 'ERR_TLS_CERT_ALTNAME_INVALID', host);
    assert.equal(error?.reason, 'Host is a non-canonical IP address', host);
  }
  assert.equal(tls.checkServerIdentity('127.0.0.1', {
    subjectaltname: 'IP Address:127.0.0.1', subject: {},
  }), undefined);
  assert.equal(tls.checkServerIdentity('1.2.3.example', {
    subjectaltname: 'DNS:1.2.3.example', subject: {},
  }), undefined);
});
