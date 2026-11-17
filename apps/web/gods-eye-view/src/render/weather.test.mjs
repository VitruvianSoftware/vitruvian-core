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
import { test } from 'node:test';

import { CLEAR_WEATHER, mergeWeather } from './weather.js';

test('clear weather draws nothing', () => {
  for (const key of ['clouds', 'fog', 'haze', 'rain', 'snow'])
    assert.equal(CLEAR_WEATHER[key], 0, key);
  assert.deepEqual(CLEAR_WEATHER.wind, { speedMps: 0, fromDeg: 0 });
});

test('a set keeps what it is not given and clamps strengths', () => {
  const a = mergeWeather(CLEAR_WEATHER, { clouds: 0.4, rain: 3 });
  assert.equal(a.clouds, 0.4);
  assert.equal(a.rain, 1);
  const b = mergeWeather(a, { fog: -1, snow: Number.NaN });
  assert.equal(b.fog, 0);
  assert.equal(b.snow, 0);
  assert.equal(b.clouds, 0.4, 'clouds kept');
  assert.equal(b.rain, 1, 'rain kept');
});

test('wind is taken whole, its speed at least 0, its direction wrapped', () => {
  const a = mergeWeather(CLEAR_WEATHER, {
    wind: { speedMps: 12, fromDeg: -90 },
  });
  assert.deepEqual(a.wind, { speedMps: 12, fromDeg: 270 });
  const b = mergeWeather(a, { wind: { speedMps: -3, fromDeg: 725 } });
  assert.deepEqual(b.wind, { speedMps: 0, fromDeg: 5 });
  const c = mergeWeather(b, { clouds: 1 });
  assert.deepEqual(c.wind, b.wind, 'wind kept');
  assert.notEqual(c.wind, b.wind, 'a copy');
});
