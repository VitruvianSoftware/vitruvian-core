/**
 * Copyright (c) 2026 VitruvianSoftware
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { splitMessage, markdownToTelegramHtml, formatResponse } from './formatter.js';

// ─── splitMessage ────────────────────────────────────────────────────────────

test('splitMessage returns a single chunk when under the limit', () => {
  assert.deepEqual(splitMessage('hello world'), ['hello world']);
});

test('splitMessage splits long text into chunks that each fit the limit', () => {
  const text = 'a'.repeat(50);
  const chunks = splitMessage(text, 10);
  assert.ok(chunks.length > 1, 'should split');
  for (const c of chunks) assert.ok(c.length <= 10, `chunk of ${c.length} exceeds 10`);
  assert.equal(chunks.join(''), text, 'chunks reassemble to the original');
});

test('splitMessage prefers a paragraph (double-newline) boundary', () => {
  const para1 = 'x'.repeat(60);
  const para2 = 'y'.repeat(60);
  const [first] = splitMessage(`${para1}\n\n${para2}`, 100);
  assert.equal(first, `${para1}\n\n`, 'breaks after the double newline');
});

test('splitMessage falls back to a space boundary when no newline fits', () => {
  const chunks = splitMessage('word '.repeat(30).trim(), 20);
  for (const c of chunks) assert.ok(c.length <= 20);
  // no chunk should start mid-word (each break was at a space)
  assert.ok(chunks.slice(1).every((c) => !c.startsWith(' ')));
});

// ─── markdownToTelegramHtml ──────────────────────────────────────────────────

test('markdownToTelegramHtml converts bold and italic', () => {
  assert.equal(markdownToTelegramHtml('**bold**'), '<b>bold</b>');
  assert.equal(markdownToTelegramHtml('__bold__'), '<b>bold</b>');
  assert.equal(markdownToTelegramHtml('*italic*'), '<i>italic</i>');
});

test('markdownToTelegramHtml escapes HTML metacharacters in plain text', () => {
  assert.equal(markdownToTelegramHtml('a < b & c > d'), 'a &lt; b &amp; c &gt; d');
});

test('markdownToTelegramHtml converts links', () => {
  assert.equal(
    markdownToTelegramHtml('[docs](https://example.com)'),
    '<a href="https://example.com">docs</a>',
  );
});

test('markdownToTelegramHtml protects inline code and escapes inside it', () => {
  assert.equal(markdownToTelegramHtml('`a < b`'), '<code>a &lt; b</code>');
});

test('markdownToTelegramHtml renders fenced code blocks with a language class', () => {
  const out = markdownToTelegramHtml('```js\nconst x = 1 < 2;\n```');
  assert.match(out, /^<pre><code class="language-js">/);
  assert.match(out, /const x = 1 &lt; 2;/, 'code contents are html-escaped');
});

test('markdownToTelegramHtml converts headings to bold', () => {
  assert.equal(markdownToTelegramHtml('## Title'), '<b>Title</b>');
});

// ─── formatResponse ──────────────────────────────────────────────────────────

test('formatResponse returns HTML parse mode for convertible markdown', () => {
  const r = formatResponse('**hi**');
  assert.equal(r.parseMode, 'HTML');
  assert.equal(r.text, '<b>hi</b>');
});

test('formatResponse is a total function (never throws) on arbitrary input', () => {
  assert.doesNotThrow(() => formatResponse('```unterminated'));
});
