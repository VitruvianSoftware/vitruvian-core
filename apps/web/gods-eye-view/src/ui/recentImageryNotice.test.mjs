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

// Box-tool and model refusals on the Recent Imagery notice line are
// shown in the UI language; the layer keeps them in English.
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { setLocale } from '../i18n/index.js';
import { validateBox } from '../layers/recentImagery/model.js';
import { localizeNotice } from './recentImagery.js';

const REFUSALS = [
  'Drag to size the box', // imageryBoxTool.js, click without drag
  'Press on the ground, not the sky', // imageryBoxTool.js
  'Point the camera at the ground to use the view', // layers/recentImagery/index.js
  'That point cannot anchor a box', // layers/recentImagery/index.js
  ...[
    { west: 170, south: 10, east: -170, north: 20 }, // dateline, over the size cap
    { west: 10, south: 80, east: 20, north: 89 },
    { west: 10, south: 10, east: 10, north: 20 },
    { west: 10, south: 10, east: 200, north: 20 },
    { west: Number.NaN, south: 10, east: 20, north: 20 },
  ].map((box) => {
    const result = validateBox(box);
    assert.equal(result.ok, false);
    return result.message;
  }),
];

test('en: refusals stay English', () => {
  setLocale('en');
  for (const text of REFUSALS) {
    const shown = localizeNotice(text);
    // Size refusals are rewritten with a non-breaking space before the unit.
    const expected = / km wide/.test(text)
      ? text.replaceAll(' km', '\u00a0km')
      : text;
    assert.equal(shown, expected);
  }
  assert.ok(REFUSALS.includes('Imagery stops at ±85.05° latitude'));
});

for (const locale of ['es', 'ru']) {
  test(`${locale}: box-tool and model refusals are translated`, () => {
    setLocale(locale);
    try {
      for (const text of REFUSALS)
        assert.notEqual(localizeNotice(text), text, `untranslated: ${text}`);
      assert.match(
        localizeNotice('Imagery stops at ±85.05° latitude'),
        /85,05/,
      );
    } finally {
      setLocale('en');
    }
  });
}
