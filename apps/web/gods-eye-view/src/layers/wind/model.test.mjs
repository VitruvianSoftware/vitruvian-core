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
import { advectParticle, sampleWind, windColor } from './model.js';

const field = {
  u: Float32Array.from([1, 2, 3, 4]),
  v: Float32Array.from([5, 6, 7, 8]),
  nx: 2,
  ny: 2,
  lo1: 0,
  la1: 90,
  dx: 180,
  dy: 90,
};

test('sampleWind interpolates, wraps, clamps, and rejects non-finite input', () => {
  assert.deepEqual(sampleWind(field, 0, 90), { u: 1, v: 5 });
  assert.deepEqual(sampleWind(field, 90, 45), { u: 2.5, v: 6.5 });
  assert.deepEqual(sampleWind(field, 359.99, 90), sampleWind(field, -0.01, 90));
  assert.deepEqual(sampleWind(field, 0, 100), { u: 1, v: 5 });
  assert.deepEqual(sampleWind(field, Infinity, 0), { u: 0, v: 0 });
});

test('advectParticle moves and constrains particles', () => {
  const particle = { lon: 179, lat: 88 };
  advectParticle(particle, { u: 10, v: 100 }, 3600);
  assert.ok(particle.lon < 0);
  assert.equal(particle.lat, 89);
});

test('windColor returns a monotonic ramp string', () => {
  assert.equal(typeof windColor(0), 'string');
  assert.notEqual(windColor(0), windColor(30));
});
