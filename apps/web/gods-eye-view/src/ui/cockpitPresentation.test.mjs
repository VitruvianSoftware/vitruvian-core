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
  formatCockpitDistance,
  formatCockpitWindDirection,
  tleAgeParts,
} from './cockpitPresentation.js';

test('wind just west of north reads 0°, not 360°', () => {
  assert.equal(formatCockpitWindDirection(90), 'E · 90°');
  assert.equal(formatCockpitWindDirection(0), 'N · 0°');
  assert.equal(formatCockpitWindDirection(359.4), 'N · 359°');
  assert.equal(formatCockpitWindDirection(359.6), 'N · 0°');
});

test('a cockpit distance that rounds to 10.0 km drops the decimal', () => {
  assert.match(formatCockpitDistance(9949), /^9\.9\s?KM$/);
  assert.match(formatCockpitDistance(9960), /^10\s?KM$/);
});

test('a TLE age reads under an hour, then whole hours, then whole days', () => {
  const HOUR = 3_600_000;
  assert.deepEqual(tleAgeParts(0), { unit: 'under-hour' });
  assert.deepEqual(tleAgeParts(59 * 60_000), { unit: 'under-hour' });
  assert.deepEqual(tleAgeParts(HOUR), { unit: 'hours', value: 1 });
  assert.deepEqual(tleAgeParts(13.9 * HOUR), { unit: 'hours', value: 13 });
  assert.deepEqual(tleAgeParts(24 * HOUR - 1), { unit: 'hours', value: 23 });
  assert.deepEqual(tleAgeParts(24 * HOUR), { unit: 'days', value: 1 });
  assert.deepEqual(tleAgeParts(50 * HOUR), { unit: 'days', value: 2 });
  // A clock a little behind the epoch is still fresh, not negative.
  assert.deepEqual(tleAgeParts(-5 * 60_000), { unit: 'under-hour' });
  assert.equal(tleAgeParts(null), null);
  assert.equal(tleAgeParts(Number.NaN), null);
});
