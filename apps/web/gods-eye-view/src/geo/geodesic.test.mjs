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
import * as Cesium from 'cesium';
import test from 'node:test';
import { geodesicAt, surfaceDistance } from './geodesic.js';

test('surface distance matches the default renderer’s geodesic', () => {
  let seed = 11;
  const random = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
  const d = Math.PI / 180;
  const geodesic = new Cesium.EllipsoidGeodesic();
  for (let i = 0; i < 400; i++) {
    const start = {
      lon: (random() * 360 - 180) * d,
      lat: (random() * 170 - 85) * d,
    };
    // Near pairs, as a nearby-sites query asks, and far ones short of antipodal.
    const reach = i % 2 ? 2 : 120;
    const end = {
      lon: start.lon + (random() * 2 - 1) * reach * d,
      lat:
        Math.max(
          -89,
          Math.min(89, start.lat / d + (random() * 2 - 1) * reach),
        ) * d,
    };
    geodesic.setEndPoints(
      new Cesium.Cartographic(start.lon, start.lat, 0),
      new Cesium.Cartographic(end.lon, end.lat, 0),
    );
    const expected = geodesic.surfaceDistance;
    assert.ok(
      Math.abs(surfaceDistance(start, end) - expected) <=
        1e-9 * Math.max(1, expected),
      `${i}: ${surfaceDistance(start, end)} vs ${expected}`,
    );
  }
});

test('the same point is no distance away, and nearly antipodal points still answer', () => {
  const p = { lon: 0.3, lat: 0.7 };
  assert.equal(surfaceDistance(p, p), 0);
  const far = surfaceDistance(
    { lon: 0, lat: 0 },
    { lon: Math.PI - 1e-9, lat: 0 },
  );
  assert.ok(Number.isFinite(far) && far > 1.9e7);
});

test('a point along the geodesic is the default renderer’s', () => {
  let seed = 23;
  const random = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
  const d = Math.PI / 180;
  for (let i = 0; i < 200; i++) {
    const start = new Cesium.Cartographic(
      (random() * 360 - 180) * d,
      (random() * 170 - 85) * d,
    );
    const reach = i % 2 ? 3 : 90;
    const end = new Cesium.Cartographic(
      start.longitude + (random() * 2 - 1) * reach * d,
      Math.max(
        -89,
        Math.min(89, start.latitude / d + (random() * 2 - 1) * reach),
      ) * d,
    );
    const geodesic = new Cesium.EllipsoidGeodesic(start, end);
    for (const fraction of [0, 0.25, 0.5, 0.9, 1]) {
      const theirs = geodesic.interpolateUsingFraction(fraction);
      const ours = geodesicAt(
        start.longitude,
        start.latitude,
        end.longitude,
        end.latitude,
        fraction,
      );
      assert.ok(
        Math.abs(ours.lon - theirs.longitude) <= 1e-12 &&
          Math.abs(ours.lat - theirs.latitude) <= 1e-12,
        `${i} @ ${fraction}: ${ours.lon},${ours.lat} vs ${theirs.longitude},${theirs.latitude}`,
      );
    }
  }
});
