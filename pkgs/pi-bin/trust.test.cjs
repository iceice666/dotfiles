const assert = require('node:assert/strict');
const { execFileSync, spawn } = require('node:child_process');
const { mkdtempSync, mkdirSync, readFileSync, rmSync } = require('node:fs');
const https = require('node:https');
const { X509Certificate } = require('node:crypto');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const { once } = require('node:events');

(async () => {
  if (process.argv[2]) {
    const blocked = new Set([
      'd7a7a0fb5d7e2731d771e9484ebcdef71d5f0c3e0a2948782bc83ee0ea699ef4',
      '86a1ecba089c4a8d3bbe2734c612ba341d813e043cf9e8a862cd5c57a36bbe6b',
      '125609aa301da0a249b97a8239cb6a34216f44dcac9f3954b14292f2e8c8608f',
      'bc4d809b15189d78db3e1d8cf4f9726a795da1643ca5f1358e1ddb0edc0d7eb3',
    ]);
    const certificates = readFileSync(process.argv[2], 'utf8').match(/-----BEGIN CERTIFICATE-----[\s\S]*?-----END CERTIFICATE-----/g);
    assert.ok(certificates?.length > 0, 'production CA bundle must contain certificates');
    for (const pem of certificates) {
      const certificate = new X509Certificate(pem);
      const fingerprint = certificate.fingerprint256.replaceAll(':', '').toLowerCase();
      assert.ok(!blocked.has(fingerprint), `blocked trust anchor: ${certificate.subject}`);
    }
    console.log('Pi production CA bundle excludes all four blocked root fingerprints');
  }
  const dir = mkdtempSync(join(tmpdir(), 'pi-trust-'));
  const servers = [];
  try {
    mkdirSync(join(dir, 'empty'));
    for (const name of ['trusted', 'untrusted']) {
      execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1', '-subj', '/CN=localhost', '-addext', 'subjectAltName=IP:127.0.0.1', '-keyout', join(dir, `${name}.key`), '-out', join(dir, `${name}.pem`)], { stdio: 'ignore' });
      const server = https.createServer({ key: readFileSync(join(dir, `${name}.key`)), cert: readFileSync(join(dir, `${name}.pem`)) }, (_req, res) => res.end('ok'));
      server.listen(0, '127.0.0.1');
      await once(server, 'listening');
      servers.push(server);
    }
    const code = `const assert=require('node:assert/strict'); (async()=>{assert.equal((await fetch('https://127.0.0.1:${servers[0].address().port}')).status,200);await assert.rejects(fetch('https://127.0.0.1:${servers[1].address().port}'),e=>e.cause?.code==='DEPTH_ZERO_SELF_SIGNED_CERT');})().catch(e=>{console.error(e);process.exitCode=1});`;
    const child = spawn(process.execPath, ['--use-openssl-ca', '-e', code], {
      stdio: 'inherit',
      env: { ...process.env, NODE_OPTIONS: '', NODE_EXTRA_CA_CERTS: '', NIX_SSL_CERT_FILE: join(dir, 'trusted.pem'), SSL_CERT_FILE: join(dir, 'trusted.pem'), SSL_CERT_DIR: join(dir, 'empty') },
    });
    const [status] = await once(child, 'exit');
    assert.equal(status, 0);
    console.log('Pi Node trust: accepts selected CA; rejects unrelated CA');
  } finally {
    for (const server of servers) server.closeAllConnections();
    for (const server of servers) server.close();
    rmSync(dir, { recursive: true, force: true });
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
