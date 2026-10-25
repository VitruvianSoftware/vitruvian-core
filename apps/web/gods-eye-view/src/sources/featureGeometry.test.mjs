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
import { approximateDistanceM } from './featureGeometry.js';

test('approximate distance takes the short way round 180°', () => {
  // Lau Islands (-179.0) to Savusavu (179.33): about 178 km apart.
  const across = approximateDistanceM(-17.5, -179.0, -16.78, 179.33);
  assert.ok(across > 150_000 && across < 200_000, String(across));
  assert.equal(
    Math.round(approximateDistanceM(0, 179.9, 0, -179.9)),
    Math.round(approximateDistanceM(0, -0.1, 0, 0.1)),
  );
  // Away from 180° nothing changes.
  assert.equal(Math.round(approximateDistanceM(0, 0, 0, 1)), 111_320);
});
