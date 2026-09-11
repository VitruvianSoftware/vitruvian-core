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

import { calculateLogoGaze } from './logoGaze.js';

const rect = { left: 100, top: 50, width: 80, height: 40 };

test('logo gaze is neutral when the cursor is centered', () => {
  assert.deepEqual(calculateLogoGaze(140, 70, rect), { x: 0, y: 0 });
});

test('logo gaze follows direction and caps at the requested offset', () => {
  const gaze = calculateLogoGaze(1140, 70, rect, 28);
  assert.ok(Math.abs(gaze.x - 28) < 1e-9);
  assert.equal(gaze.y, 0);
});

test('logo gaze uses the more visible default travel', () => {
  const gaze = calculateLogoGaze(1140, 70, rect);
  assert.ok(Math.abs(gaze.x - 34) < 1e-9);
  assert.equal(gaze.y, 0);
});

test('logo gaze ramps proportionally inside the full-gaze distance', () => {
  const gaze = calculateLogoGaze(300, 70, rect, 28);
  assert.ok(Math.abs(gaze.x - 14) < 1e-9);
  assert.equal(gaze.y, 0);
});

test('logo gaze preserves diagonal direction while staying bounded', () => {
  const gaze = calculateLogoGaze(640, 570, rect, 28);
  assert.ok(Math.abs(Math.hypot(gaze.x, gaze.y) - 28) < 1e-9);
  assert.ok(gaze.x > 0);
  assert.ok(gaze.y > 0);
});

test('logo gaze fails closed for invalid geometry', () => {
  assert.deepEqual(calculateLogoGaze(10, 10, { ...rect, width: 0 }), { x: 0, y: 0 });
  assert.deepEqual(calculateLogoGaze(Number.NaN, 10, rect), { x: 0, y: 0 });
});
