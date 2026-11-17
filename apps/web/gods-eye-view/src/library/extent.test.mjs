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
  WORLD_EXTENT,
  coverageExtent,
  featureExtent,
  isWorldScale,
  padExtent,
} from './extent.js';

const point = (lon, lat) => ({
  geometry: { type: 'Point', coordinates: [lon, lat] },
});

test('the extent covers every coordinate, nested geometries included', () => {
  assert.deepEqual(
    featureExtent([
      point(-122, 37),
      {
        geometry: {
          type: 'Polygon',
          coordinates: [
            [
              [-80, 25],
              [-79, 25],
              [-79, 26],
              [-80, 25],
            ],
          ],
        },
      },
      { geometry: null },
      point(500, 0),
    ]),
    { west: -122, south: 25, east: -79, north: 37 },
  );
  assert.equal(featureExtent([]), null);
  assert.equal(featureExtent([{ geometry: { coordinates: [NaN, 1] } }]), null);
});

test('a set straddling the antimeridian takes the short way round', () => {
  assert.deepEqual(featureExtent([point(178, -17), point(-179, -16)]), {
    west: 178,
    south: -17,
    east: 181,
    north: -16,
  });
  assert.deepEqual(featureExtent([point(-170, 0), point(-160, 1)]), {
    west: -170,
    south: 0,
    east: -160,
    north: 1,
  });
});

test('coverage falls back to the world, a point grows to a frameable box', () => {
  assert.deepEqual(
    coverageExtent({ coverage: { global: true } }),
    WORLD_EXTENT,
  );
  assert.deepEqual(coverageExtent({ coverage: { bbox: [1, 2, 3, 4] } }), {
    west: 1,
    south: 2,
    east: 3,
    north: 4,
  });
  const padded = padExtent({ west: 10, south: 20, east: 10, north: 20 });
  assert.ok(Math.abs(padded.east - padded.west - 0.05) < 1e-9);
  assert.equal(
    padExtent({ west: 0, south: -89, east: 1, north: 89 }).north,
    85,
  );
  assert.equal(isWorldScale(WORLD_EXTENT), true);
  assert.equal(isWorldScale({ west: -125, east: -66 }), false);
});
