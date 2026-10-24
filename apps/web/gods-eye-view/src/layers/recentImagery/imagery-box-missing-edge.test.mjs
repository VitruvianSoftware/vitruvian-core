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

import test from 'node:test';
import assert from 'node:assert/strict';
import {
  boxCentre,
  boxFromRectangle,
  dequantizeBox,
  validateBox,
} from './model.js';
import { searchHls } from './catalog.js';

test('missing imagery edges do not turn into invented zero coordinates', () => {
  for (const value of [null, undefined, '', ' ', false, true]) {
    const box = { west: value, south: 0, east: 1, north: 1 };
    assert.equal(validateBox(box).ok, false);
    assert.equal(validateBox(box).reason, 'invalid');
    assert.equal(boxCentre(box), null);
  }
  assert.equal(validateBox({ west: 0, south: 0, east: 1, north: 1 }).ok, true);
  assert.equal(
    validateBox({ west: '0', south: '0', east: '1', north: '1' }).ok,
    true,
  );
});

test('every edge and every box entry point refuses a missing edge', async () => {
  const blanks = [null, undefined, '', ' ', false, [], {}];
  for (const edge of ['west', 'south', 'east', 'north']) {
    for (const value of blanks) {
      const box = { west: 1, south: 1, east: 2, north: 2, [edge]: value };
      assert.equal(validateBox(box).ok, false, `${edge}=${String(value)}`);
      // Share-link integers and Cesium radians are converted per edge.
      assert.equal(dequantizeBox(box), null, `share ${edge}`);
      assert.equal(boxFromRectangle(box), null, `radians ${edge}`);
    }
  }
  let fetched = false;
  await assert.rejects(
    searchHls({
      box: { west: ' ', south: 1, east: 2, north: 2 },
      fetchImpl: async () => {
        fetched = true;
      },
    }),
    TypeError,
  );
  assert.equal(fetched, false);
  assert.ok(dequantizeBox({ west: 0, south: 0, east: 100000, north: 100000 }));
});
