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
  approxDistanceKm,
  GROUND_FLOOR_CLAMP_RADIUS_KM,
} from './recordPolicy.js';

test('approximate distance takes the short way across the antimeridian', () => {
  // 0.2° of longitude at Taveuni, Fiji (16.8° S) is about 21 km.
  for (const [lon1, lon2] of [
    [179.9, -179.9],
    [-179.9, 179.9],
  ]) {
    const km = approxDistanceKm(-16.8, lon1, -16.8, lon2);
    assert.ok(Math.abs(km - 21.31) < 0.01, `${lon1} → ${lon2}: ${km} km`);
    assert.ok(km <= GROUND_FLOOR_CLAMP_RADIUS_KM);
  }
});
