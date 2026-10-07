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
import { decodeParams, encodeParams } from './params.js';

test('encodeParams writes one boolean per provider plus the filter', () => {
  assert.deepEqual(
    encodeParams({
      providers: [
        ['mapillary', true],
        ['panoramax', false],
      ],
      filter: { pano: 'flat', sinceDays: 365 },
    }),
    { mapillary: true, panoramax: false, pano: 'flat', sinceDays: 365 },
  );
});

test('decodeParams round-trips and ignores unknown or malformed keys', () => {
  const current = { pano: 'all', sinceDays: 0 };
  const decoded = decodeParams(
    { mapillary: false, kartaview: true, pano: 'pano', sinceDays: 730, x: 1 },
    { providerIds: ['mapillary'], filter: current },
  );
  assert.deepEqual([...decoded.providers], [['mapillary', false]]);
  assert.deepEqual(decoded.filter, { pano: 'pano', sinceDays: 730 });

  const partial = decodeParams(
    { mapillary: '1', pano: 'weird' },
    { providerIds: ['mapillary'], filter: { pano: 'flat', sinceDays: 5 } },
  );
  assert.equal(partial.providers.size, 0, 'a string is not a switch');
  assert.deepEqual(partial.filter, { pano: 'flat', sinceDays: 5 });

  const empty = decodeParams(null, {
    providerIds: ['mapillary'],
    filter: current,
  });
  assert.equal(empty.providers.size, 0);
  assert.deepEqual(empty.filter, current);
});

test('decodeParams applies "any date" (0 days) over a current window (share-link defaults)', () => {
  const decoded = decodeParams(
    { sinceDays: 0 },
    { providerIds: ['mapillary'], filter: { pano: 'flat', sinceDays: 365 } },
  );
  assert.deepEqual(decoded.filter, { pano: 'flat', sinceDays: 0 });
  // The provider switch off is a value too, not an absence.
  assert.deepEqual(
    [
      ...decodeParams(
        { mapillary: false },
        { providerIds: ['mapillary'], filter: { pano: 'all', sinceDays: 0 } },
      ).providers,
    ],
    [['mapillary', false]],
  );
});
