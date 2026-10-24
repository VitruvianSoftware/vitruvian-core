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
import { mapillaryImageUrl } from './policy.js';
import { sequenceIdFromPick } from '../../lineCoverage.js';
import { thinImages } from '../../sequenceCones.js';

test('image deep links match the mapillary.com share format', () => {
  assert.equal(
    mapillaryImageUrl(1814275685699406),
    'https://www.mapillary.com/app/?pKey=1814275685699406&focus=photo',
  );
  assert.equal(mapillaryImageUrl('  '), 'https://www.mapillary.com/app/');
});

test('a sequence line pick names its sequence; other picks do not', () => {
  assert.equal(sequenceIdFromPick('mly:seq:abc', 'mly:seq:'), 'abc');
  assert.equal(sequenceIdFromPick('mly:img:abc', 'mly:seq:'), null);
  assert.equal(sequenceIdFromPick(null, 'mly:seq:'), null);
});

test('cone thinning across the date line drops images metres apart', () => {
  const image = (id, lon) => ({ id, lon, lat: 0 });
  // A sequence driving east over ±180° with images ~1 m apart, then ~11 m on.
  const kept = thinImages(
    [
      image('a', 179.99999),
      image('b', -179.99999), // ~2 m from a, across the date line
      image('c', -179.9999), // ~11 m from a
    ],
    3,
  );
  assert.deepEqual(
    kept.map(({ id }) => id),
    ['a', 'c'],
  );
});
