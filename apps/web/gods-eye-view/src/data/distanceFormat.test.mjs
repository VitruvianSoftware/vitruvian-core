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
  distanceParts,
  formatDistanceText,
  kilometreDigits,
} from './distanceFormat.js';

test('a distance switches to kilometres where its metres round to 1,000', () => {
  assert.equal(formatDistanceText(999.4), '999 m');
  assert.equal(formatDistanceText(999.5), '1.0 km');
  assert.equal(formatDistanceText(999.6), '1.0 km');
  assert.equal(formatDistanceText(994, { metreStep: 10 }), '990 m');
  assert.equal(formatDistanceText(995, { metreStep: 10 }), '1.0 km');
});

test('kilometres drop their decimal where the tenth rounds to 10.0', () => {
  assert.equal(kilometreDigits(9949), 1);
  assert.equal(kilometreDigits(9950), 0);
  assert.equal(formatDistanceText(9949), '9.9 km');
  assert.equal(formatDistanceText(9950), '10 km');
  assert.equal(formatDistanceText(9960), '10 km');
  assert.equal(formatDistanceText(99950), '100 km');
});

test('metres below exactBelowM stay whole while the rest round to the step', () => {
  const options = { metreStep: 10, exactBelowM: 100 };
  assert.equal(formatDistanceText(8, options), '8 m');
  assert.equal(formatDistanceText(99.4, options), '99 m');
  assert.equal(formatDistanceText(846, options), '850 m');
  assert.deepEqual(distanceParts(846, options), {
    value: 850,
    unit: 'm',
    digits: 0,
  });
});

test('a negative or non-finite distance has no parts', () => {
  for (const value of [-1, Number.NaN, Infinity, -Infinity, null, undefined]) {
    assert.equal(distanceParts(value), null);
    assert.equal(formatDistanceText(value), null);
  }
  assert.equal(formatDistanceText(0), '0 m');
});

test('kilometres come back rounded, so toFixed and Intl agree', () => {
  assert.deepEqual(distanceParts(1450), { value: 1.5, unit: 'km', digits: 1 });
  assert.equal(formatDistanceText(1450), '1.5 km');
  assert.equal(formatDistanceText(1150), '1.2 km');
});
