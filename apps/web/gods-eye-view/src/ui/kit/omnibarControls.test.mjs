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

// The Omnibar's buttons and Material glyphs are the kit's: its template
// hand-writes no <button> and no Material Symbols span. Its two inline SVG
// glyphs (the mic and the chat row's bubble) are not Material symbols the
// page loads, so they stay as they are drawn.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = readFileSync(
  new URL('../views/panels/Omnibar.vue', import.meta.url),
  'utf8',
);
/** The template block: everything outside script and style. */
const template = source.replace(/<(script|style)\b[\s\S]*?<\/\1\s*>/g, '');

test('the Omnibar hand-writes no button; each is a UiButton', () => {
  assert.deepEqual(template.match(/<button\b/gi) ?? [], []);
  assert.equal(template.match(/<UiButton\b/g)?.length, 2);
});

test('the Omnibar hand-writes no Material glyph; each is a UiIcon', () => {
  assert.deepEqual(template.match(/material-symbols-outlined/g) ?? [], []);
  const icons = template.match(/<UiIcon\b[^>]*>/g) ?? [];
  assert.equal(icons.length, 3);
  // Without it the kit writes an 18px size that beats the Omnibar's own rules.
  for (const icon of icons) assert.match(icon, /:size="null"/);
});

test('the only inline SVG glyphs are the mic and the chat row bubble', () => {
  const svgs = [...template.matchAll(/<svg\b[\s\S]*?<\/svg\s*>/g)].map(
    (m) => m[0],
  );
  assert.equal(svgs.length, 2);
  assert.match(svgs[0], /<rect x="9" y="3" width="6" height="11" rx="3" \/>/);
  assert.match(svgs[1], /class="omnibar-item-icon"/);
  assert.match(svgs[1], /<path d="M4 5h16v11H9l-5 4z" \/>/);
});
