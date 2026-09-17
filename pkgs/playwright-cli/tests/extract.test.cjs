const assert = require('node:assert/strict');
const { test } = require('node:test');
const vm = require('node:vm');
const { parseHTML } = require('linkedom');
const { extractionExpression, parseResult } = require('../extract.cjs');

function extract(html, max = 24000) {
  const { document, window } = parseHTML(html);
  Object.defineProperty(document, 'baseURI', { value: 'https://example.test/docs/' });
  const original = document.toString();
  const result = vm.runInNewContext(`(${extractionExpression(max)})()`, {
    document, window, URL, location: { href: 'https://example.test/docs/page' },
  });
  assert.equal(document.toString(), original, 'extraction must not mutate the live DOM');
  return result;
}

test('article extraction produces Markdown, source metadata and absolute links', () => {
  const paragraphs = '<p>This is an article with enough readable sentences to identify its main content. It explains browser automation and careful extraction of source evidence.</p>'.repeat(10);
  const result = extract(`<html><head><title>Research</title></head><body><nav>Menu</nav><article><h1>Research</h1>${paragraphs}<a href="next">Next</a><script>SECRET_SCRIPT</script></article></body></html>`);
  assert.equal(result.untrusted, true);
  assert.equal(result.extraction, 'readability');
  assert.match(result.markdown, /https:\/\/example.test\/docs\/next/);
  assert.doesNotMatch(result.markdown, /SECRET_SCRIPT/);
  assert.equal(result.truncated, false);
});

test('output bound is explicit', () => {
  const result = extract('<html><head><title>Bound</title></head><body><main><p>Hello world</p></main></body></html>', 5);
  assert.equal(result.markdown.length, 5);
  assert.equal(result.truncated, true);
  assert.ok(result.totalCharacters > 5);
});

test('unsafe links are removed without dropping their text', () => {
  const result = extract('<html><head><title>Links</title></head><body><main><a href="javascript:alert(1)">click</a><a href="file:///secret">file</a><img src="data:text/html,secret"></main></body></html>');
  assert.match(result.markdown, /click/);
  assert.doesNotMatch(result.markdown, /javascript:|file:\/\/|data:text/);
});

test('empty document uses the explicit fallback', () => {
  const result = extract('<html><head><title>Empty</title></head><body><main></main></body></html>');
  assert.equal(result.extraction, 'main-or-body-fallback');
  assert.equal(result.markdown, '');
});

test('reject invalid limits', () => {
  for (const value of [0, -1, NaN, 1.5, 200001]) assert.throws(() => extractionExpression(value));
});

test('parse only result section, not echoed extraction code', () => {
  const data = { untrusted: true, url: 'https://example.test', markdown: '# Content' };
  assert.deepEqual(parseResult(`### Result\n${JSON.stringify(data)}\n### Ran Playwright code\nlarge source`), data);
  assert.deepEqual(parseResult(`### Result\n${JSON.stringify(data)}\n`), data);
  assert.throws(() => parseResult('### Error\nnot open'));
  assert.throws(() => parseResult('### Result\n{}\n'));
});
