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
import { normalizeHeading, roundHeadingDegrees } from './headingDegrees.js';

test('normalizeHeading wraps into [0, 360) and reads a non-finite value as 0', () => {
  assert.equal(normalizeHeading(370), 10);
  assert.equal(normalizeHeading(-10), 350);
  assert.equal(normalizeHeading(720), 0);
  assert.equal(normalizeHeading(Number.NaN), 0);
  assert.equal(normalizeHeading(Infinity), 0);
});

test('roundHeadingDegrees reads 359.5° and above as north, never 360', () => {
  assert.equal(roundHeadingDegrees(359.4), 359);
  assert.equal(roundHeadingDegrees(359.5), 0);
  assert.equal(roundHeadingDegrees(359.6), 0);
  assert.equal(roundHeadingDegrees(360), 0);
  assert.equal(roundHeadingDegrees(0), 0);
  assert.equal(roundHeadingDegrees(194.2), 194);
});

test('roundHeadingDegrees wraps negative and multi-turn bearings', () => {
  assert.equal(Object.is(roundHeadingDegrees(-0.4), 0), true);
  assert.equal(roundHeadingDegrees(-0.6), 359);
  assert.equal(roundHeadingDegrees(-1), 359);
  assert.equal(roundHeadingDegrees(719.6), 0);
  assert.equal(roundHeadingDegrees(-360.6), 359);
});

test('roundHeadingDegrees returns null for a value that is not finite', () => {
  for (const value of [
    Number.NaN,
    Infinity,
    -Infinity,
    null,
    undefined,
    '12',
  ]) {
    assert.equal(roundHeadingDegrees(value), null);
  }
});

test('normalizeHeading keeps a positive bearing just under a half degree', () => {
  assert.equal(roundHeadingDegrees(0.49999999999999), 0);
  assert.equal(roundHeadingDegrees(359.49999999999994), 359);
  assert.equal(normalizeHeading(-1e-15) < 360, true);
});
