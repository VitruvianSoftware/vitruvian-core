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

// Every checkbox in a Vue view is a UiCheckbox: no SFC template hand-writes
// `<input type="checkbox">`.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SRC_ROOT = fileURLToPath(new URL('../../', import.meta.url));
const REPO_ROOT = path.resolve(SRC_ROOT, '..');
const NOT_YET = new Set(['src/ui/kit/UiCheckbox.vue']);

/** Every SFC under src. */
function sfcFiles(directory = SRC_ROOT) {
  const files = [];
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...sfcFiles(absolute));
    else if (entry.isFile() && entry.name.endsWith('.vue'))
      files.push(absolute);
  }
  return files.sort();
}

/** The template block: everything outside script and style. */
function template(source) {
  return source.replace(/<(script|style)\b[\s\S]*?<\/\1\s*>/g, '');
}

// An opening tag's attributes, quoted values may hold `>` (`() => x`).
const ATTRS = String.raw`(?:[^>"']|"[^"]*"|'[^']*')*`;
const HAND_WRITTEN_CHECKBOX = new RegExp(
  String.raw`<input\b${ATTRS}\btype="checkbox"${ATTRS}>`,
  'gi',
);

/** Hand-written checkboxes in an SFC's template. */
function handWrittenCheckboxes(source) {
  return [...template(source).matchAll(HAND_WRITTEN_CHECKBOX)].map((m) =>
    m[0].replace(/\s+/g, ' '),
  );
}

test('the scan finds each hand-written checkbox', () => {
  for (const markup of [
    '<template><input type="checkbox" id="x" @change="on" /></template>',
    '<template><input\n  :checked="a > b"\n  type="checkbox"\n/></template>',
  ])
    assert.equal(handWrittenCheckboxes(markup).length, 1, markup);
  for (const markup of [
    '<template><UiCheckbox input-id="x" v-model="on">On</UiCheckbox></template>',
    '<template><input type="search" /></template>',
    '<script>const html = \'<input type="checkbox">\';</script><template><p /></template>',
  ])
    assert.equal(handWrittenCheckboxes(markup).length, 0, markup);
});

test('no SFC hand-writes a checkbox; each is a UiCheckbox', () => {
  const found = [];
  for (const file of sfcFiles()) {
    const relative = path.relative(REPO_ROOT, file).split(path.sep).join('/');
    if (NOT_YET.has(relative)) continue;
    for (const markup of handWrittenCheckboxes(readFileSync(file, 'utf8')))
      found.push(`${relative}: ${markup}`);
  }
  assert.deepEqual(found, []);
});
