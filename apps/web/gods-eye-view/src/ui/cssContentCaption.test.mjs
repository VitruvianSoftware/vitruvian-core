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

// The CCTV "ACQUIRING FRAME" caption lives in CSS `content:` and the
// i18n scanner (scripts/i18n.mjs) never reads CSS, so es/ru show it in English.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const STYLES = path.join(HERE, 'styles');
const LOCALES = path.join(HERE, '..', 'i18n', 'locales');
// cyber.css carries decorative theme strings (LOC / GRID, SYS 06 // ...);
// street-level.css ' · ESC' is a key cap. Neither is UI copy.
const DECORATIVE = new Set(['cyber.css', 'street-level.css']);

test('no user-visible text in CSS content: outside decorative themes', () => {
  const hits = [];
  for (const file of readdirSync(STYLES)) {
    if (!file.endsWith('.css') || DECORATIVE.has(file)) continue;
    const css = readFileSync(path.join(STYLES, file), 'utf8');
    css.split('\n').forEach((line, i) => {
      if (/^\s*content:\s*['"][^'"]*[A-Za-z]{2,}/.test(line))
        hits.push(`${file}:${i + 1} ${line.trim()}`);
    });
  }
  assert.deepEqual(hits, []);
});

test('the CCTV acquisition caption has es and ru translations', () => {
  for (const lang of ['es', 'ru']) {
    const dict = JSON.parse(readFileSync(path.join(LOCALES, `${lang}.json`), 'utf8'));
    assert.ok('ACQUIRING FRAME' in dict, `${lang}.json lacks "ACQUIRING FRAME"`);
  }
});
