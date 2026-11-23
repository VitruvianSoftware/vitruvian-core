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

// The Layer Finder's buttons and Material glyphs are the kit's: its template
// hand-writes no <button>, aria-pressed, Material Symbols span or inline SVG.
// Its search field is a UiSearchField.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

/** A view's template block: everything outside script and style. */
function template(file) {
  const source = readFileSync(
    new URL(`../views/panels/${file}`, import.meta.url),
    'utf8',
  );
  return source.replace(/<(script|style)\b[\s\S]*?<\/\1\s*>/g, '');
}
const finder = template('LayerFinder.vue');

test('the Layer Finder hand-writes no button; each is a UiButton', () => {
  assert.deepEqual(finder.match(/<button\b/gi) ?? [], []);
  // Search, Filter, the Status and Category options, and the two chips.
  assert.equal(finder.match(/<UiButton\b/g)?.length, 6);
  assert.equal(finder.match(/<UiSearchField\b/g)?.length, 1);
});

test('its pressed toggles leave aria-pressed to UiButton', () => {
  assert.deepEqual(finder.match(/aria-pressed/g) ?? [], []);
  const pressed = finder.match(/<UiButton\b[^>]*:pressed=[^>]*>/g) ?? [];
  // Search and the Status and Category options.
  assert.equal(pressed.length, 3);
  // Only the options' active class follows their pressed state; Search's
  // also stays on while a query is typed, so it keeps its own binding.
  assert.equal(
    pressed.filter((tag) => tag.includes('pressed-class="active"')).length,
    2,
  );
  assert.match(
    finder,
    /id="layer-finder-search-btn"[^>]*:class="\{ active: searching \|\| query \}"/,
  );
});

test('the Layer Finder hand-writes no Material glyph; each is a UiIcon', () => {
  assert.deepEqual(finder.match(/material-symbols-outlined/g) ?? [], []);
  assert.deepEqual(finder.match(/<svg\b/gi) ?? [], []);
  const icons = finder.match(/<UiIcon\b[^>]*>/g) ?? [];
  // Search, Filter, the two option radios and the two chips' close.
  assert.equal(icons.length, 6);
  // Without it the kit writes an 18px size that beats layer-finder.css.
  for (const icon of icons) assert.match(icon, /:size="null"/);
});
