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
import {
  normalizeFilter,
  passesImageryFilter,
  resolveFilter,
  sameFilter,
} from './filter.js';
import { MAX_SINCE_DAYS } from './policy.js';

const DAY = 86_400_000;

test('normalizeFilter merges a partial change and ignores junk', () => {
  const current = { pano: 'all', sinceDays: 0 };
  assert.deepEqual(normalizeFilter({ pano: 'pano' }, current), {
    pano: 'pano',
    sinceDays: 0,
  });
  assert.deepEqual(normalizeFilter({ pano: 'sideways' }, current), current);
  assert.deepEqual(normalizeFilter({ sinceDays: 365 }, current), {
    pano: 'all',
    sinceDays: 365,
  });
  assert.deepEqual(normalizeFilter({ sinceDays: -3 }, current), current);
  assert.deepEqual(normalizeFilter({ sinceDays: 1.5 }, current), current);
  assert.deepEqual(normalizeFilter({ sinceDays: 99_999_999 }, current), {
    pano: 'all',
    sinceDays: 36_500,
  });
  assert.deepEqual(normalizeFilter(null, current), current);
  assert.deepEqual(normalizeFilter({ pano: 'flat' }), {
    pano: 'flat',
    sinceDays: 0,
  });
});

test('resolveFilter turns relative days into an absolute cut-off', () => {
  const now = Date.UTC(2026, 8, 25);
  assert.deepEqual(resolveFilter({ pano: 'all', sinceDays: 0 }, now), {
    pano: 'all',
    sinceMs: null,
  });
  assert.deepEqual(resolveFilter({ pano: 'flat', sinceDays: 10 }, now), {
    pano: 'flat',
    sinceMs: now - 10 * DAY,
  });
  assert.equal(resolveFilter({ pano: 'nope' }, now).pano, 'all');
});

test('passesImageryFilter applies panorama mode and the cut-off', () => {
  const pano = { isPano: true, capturedAt: 200 };
  const flat = { isPano: false, capturedAt: 50 };
  assert.equal(passesImageryFilter(pano, null), true);
  assert.equal(
    passesImageryFilter(pano, { pano: 'pano', sinceMs: null }),
    true,
  );
  assert.equal(
    passesImageryFilter(flat, { pano: 'pano', sinceMs: null }),
    false,
  );
  assert.equal(
    passesImageryFilter(flat, { pano: 'flat', sinceMs: null }),
    true,
  );
  assert.equal(
    passesImageryFilter(pano, { pano: 'flat', sinceMs: null }),
    false,
  );
  assert.equal(passesImageryFilter(flat, { pano: 'all', sinceMs: 100 }), false);
  assert.equal(passesImageryFilter(pano, { pano: 'all', sinceMs: 100 }), true);
  assert.equal(passesImageryFilter({}, { pano: 'all', sinceMs: 1 }), false);
});

test('sameFilter compares the stored form', () => {
  assert.equal(
    sameFilter({ pano: 'all', sinceDays: 0 }, { pano: 'all', sinceDays: 0 }),
    true,
  );
  assert.equal(
    sameFilter({ pano: 'all', sinceDays: 0 }, { pano: 'all', sinceDays: 1 }),
    false,
  );
});

test('normalizeFilter takes "any date" (0 days) over a current window (share-link defaults)', () => {
  // Dragging SINCE back to ANY DATE, or a link that says so, must stick.
  assert.equal(
    normalizeFilter({ sinceDays: 0 }, { pano: 'all', sinceDays: 365 })
      .sinceDays,
    0,
  );
  assert.equal(
    normalizeFilter(
      { sinceDays: MAX_SINCE_DAYS },
      { pano: 'all', sinceDays: 0 },
    ).sinceDays,
    MAX_SINCE_DAYS,
    'the longest window is kept whole',
  );
});
