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

// The welcome card's buttons and Material glyphs are the kit's: its template
// hand-writes no <button> and no Material Symbols span, and its one box is a
// UiCheckbox. Its two inline SVGs (God mode's globe and its callouts) are
// drawings, not glyphs, and its outbound links stay links.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = readFileSync(
  new URL('../views/WelcomeView.vue', import.meta.url),
  'utf8',
);
/** The template block: everything outside script and style. */
const template = source.replace(/<(script|style)\b[\s\S]*?<\/\1\s*>/g, '');

test('the welcome card hand-writes no button; each is a UiButton', () => {
  assert.deepEqual(template.match(/<button\b/gi) ?? [], []);
  // SKIP, the three start tiles, BROWSE STORIES, BACK and the main action.
  assert.equal(template.match(/<UiButton\b/g)?.length, 7);
  assert.equal(template.match(/<UiCheckbox\b/g)?.length, 1);
});

test('the welcome card hand-writes no Material glyph; each is a UiIcon', () => {
  assert.deepEqual(template.match(/material-symbols-outlined/g) ?? [], []);
  const icons = template.match(/<UiIcon\b[^>]*>/g) ?? [];
  // The three tiles, the three tips, the Stories card and the main arrow.
  assert.equal(icons.length, 8);
  // Without it the kit writes an 18px size that beats first-run.css's rules.
  for (const icon of icons) assert.match(icon, /:size="null"/);
});

test('the only inline SVGs are God mode preview drawings', () => {
  const svgs = [...template.matchAll(/<svg\b[^>]*>/g)].map((m) => m[0]);
  assert.equal(svgs.length, 2);
  assert.match(svgs[0], /class="first-run-globe"/);
  assert.match(svgs[1], /class="first-run-callouts"/);
});
