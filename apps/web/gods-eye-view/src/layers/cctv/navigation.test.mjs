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

import { createNavigation } from './navigation.js';

function fixture() {
  const records = [
    { camera: { id: 'west', lat: 40, lon: -120 } },
    { camera: { id: 'east', lat: 40, lon: -100 } },
  ];
  const state = { _records: records };
  const parts = {
    model: {
      eyePose: () => ({ lat: 40, lon: -101 }),
      haversineKm(lat1, lon1, lat2, lon2) {
        return Math.hypot(lat1 - lat2, lon1 - lon2);
      },
    },
  };
  const navigation = createNavigation({
    state,
    services: {},
    parts,
    source: {},
  });
  return { navigation };
}

test('nearest camera can be resolved from an explicit WGS84 target', () => {
  const { navigation } = fixture();
  assert.equal(navigation.nearestCameraIdToPoint(40, -119), 'west');
  assert.equal(navigation.nearestCameraIdToPoint(40, -101), 'east');
});

test('viewer-nearest delegates to the same target-point owner', () => {
  const { navigation } = fixture();
  assert.equal(navigation.nearestCameraIdToViewer(), 'east');
});

test('invalid target coordinates fail closed', () => {
  const { navigation } = fixture();
  for (const [lat, lon] of [
    [NaN, 0],
    [null, 0],
    [0, Infinity],
    [90.00001, 0],
    [-90.00001, 0],
    [0, 180.00001],
    [0, -180.00001],
  ]) {
    assert.equal(navigation.nearestCameraIdToPoint(lat, lon), null);
  }
});
