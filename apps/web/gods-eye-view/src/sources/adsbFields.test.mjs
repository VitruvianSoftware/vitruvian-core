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

import assert from 'node:assert/strict';
import test from 'node:test';
import { readAdsbVerticalRateFpm } from './adsbFields.js';

test('the barometric rate wins, a barometric 0 included', () => {
  assert.equal(
    readAdsbVerticalRateFpm({ baro_rate: -640, geom_rate: -832 }),
    -640,
  );
  assert.equal(readAdsbVerticalRateFpm({ baro_rate: 0, geom_rate: 600 }), 0);
});

test('a GNSS rate stands in when no barometric rate is usable', () => {
  for (const baro_rate of [
    undefined,
    null,
    Number.NaN,
    Infinity,
    '300',
    false,
  ]) {
    assert.equal(readAdsbVerticalRateFpm({ baro_rate, geom_rate: -832 }), -832);
  }
});

test('no usable rate reads as null', () => {
  assert.equal(readAdsbVerticalRateFpm({}), null);
  assert.equal(readAdsbVerticalRateFpm(null), null);
  assert.equal(
    readAdsbVerticalRateFpm({ baro_rate: '300', geom_rate: true }),
    null,
  );
});
