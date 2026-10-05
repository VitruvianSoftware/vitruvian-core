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
  VIEW_AREA_MAX_RADIUS_KM,
  VIEW_AREA_MIN_RADIUS_KM,
  viewAreaMovedEnough,
  viewAreaRadiusKm,
} from './viewArea.js';

test('the area asked for follows the camera height, and a wide view asks for every vessel', () => {
  assert.equal(viewAreaRadiusKm(2_000), VIEW_AREA_MIN_RADIUS_KM);
  assert.equal(viewAreaRadiusKm(80_000), 80);
  assert.equal(
    viewAreaRadiusKm(VIEW_AREA_MAX_RADIUS_KM * 1000),
    VIEW_AREA_MAX_RADIUS_KM,
  );
  assert.equal(viewAreaRadiusKm(VIEW_AREA_MAX_RADIUS_KM * 1000 + 1), null);
  assert.equal(viewAreaRadiusKm(Number.NaN), null);
});

test('a view asks again only after moving or zooming a quarter of its radius', () => {
  const here = { lat: 37.8, lon: -122.4, radiusKm: 40 };
  assert.equal(viewAreaMovedEnough(null, here), true);
  assert.equal(viewAreaMovedEnough(here, null), true);
  assert.equal(viewAreaMovedEnough(null, null), false);
  assert.equal(viewAreaMovedEnough(here, { ...here, lat: 37.85 }), false);
  assert.equal(viewAreaMovedEnough(here, { ...here, lat: 37.9 }), true);
  assert.equal(viewAreaMovedEnough(here, { ...here, radiusKm: 45 }), false);
  assert.equal(viewAreaMovedEnough(here, { ...here, radiusKm: 55 }), true);
});
