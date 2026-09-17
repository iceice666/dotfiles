const fs = require('node:fs');

function extractionExpression(maxChars) {
  if (!Number.isInteger(maxChars) || maxChars < 1 || maxChars > 200000) {
    throw new Error('max-chars must be an integer between 1 and 200000');
  }
  const readability = fs.readFileSync(require.resolve('@mozilla/readability/Readability.js'), 'utf8');
  const turndown = fs.readFileSync(require.resolve('turndown/lib/turndown.browser.cjs.js'), 'utf8');
  return `() => {
    const Readability = (() => { const module = { exports: {} }; ${readability}\n return module.exports; })();
    const TurndownService = (() => { const module = { exports: {} }; ${turndown}\n return module.exports; })();
    const clone = document.cloneNode(true);
    clone.querySelectorAll('script, style, noscript, iframe').forEach(node => node.remove());
    // Resolve links before detaching article HTML from its document base URI.
    clone.querySelectorAll('[href], [src]').forEach(node => {
      for (const attr of ['href', 'src']) {
        if (!node.hasAttribute(attr)) continue;
        try {
          const url = new URL(node.getAttribute(attr), document.baseURI);
          if (['http:', 'https:'].includes(url.protocol)) node.setAttribute(attr, url.href);
          else node.removeAttribute(attr);
        } catch { node.removeAttribute(attr); }
      }
    });
    const fallback = clone.querySelector('main, [role="main"]') || clone.body;
    const fallbackHtml = fallback ? fallback.innerHTML : '';
    let article;
    try { article = new Readability(clone, { maxElemsToParse: 100000 }).parse(); } catch {}
    const markdown = new TurndownService({ headingStyle: 'atx', codeBlockStyle: 'fenced' })
      .turndown(article?.content || fallbackHtml).trim();
    return {
      untrusted: true,
      url: location.href,
      title: (article?.title || document.title).slice(0, 1000),
      extraction: article?.content ? 'readability' : 'main-or-body-fallback',
      totalCharacters: markdown.length,
      truncated: markdown.length > ${maxChars},
      markdown: markdown.slice(0, ${maxChars})
    };
  }`;
}

function parseResult(output) {
  const match = output.match(/^### Result\r?\n([\s\S]*?)(?=^### |$(?![\s\S]))/m);
  if (!match) throw new Error('Playwright did not return a result; inspect the session with playwright-cli');
  const result = JSON.parse(match[1].trim());
  if (result?.untrusted !== true || typeof result.markdown !== 'string' || typeof result.url !== 'string') {
    throw new Error('Unexpected Playwright extraction result');
  }
  return result;
}

module.exports = { extractionExpression, parseResult };
