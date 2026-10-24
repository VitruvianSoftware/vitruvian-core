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
  EARTH_RADIUS_KM,
  greatCircleKm,
  greatCircleMeters,
  isGeoPoint,
} from './geoDistance.js';

const AUSTIN = Object.freeze({ lat: 30.2672, lon: -97.7431 });
const HOUSTON = Object.freeze({ lat: 29.7604, lon: -95.3698 });

test('great-circle identity and symmetry', () => {
  assert.equal(greatCircleKm(AUSTIN, AUSTIN), 0);
  assert.equal(greatCircleKm(AUSTIN, HOUSTON), greatCircleKm(HOUSTON, AUSTIN));
});

test('great-circle one-degree calibration and canonical units', () => {
  const kilometres = greatCircleKm({ lat: 0, lon: 0 }, { lat: 1, lon: 0 });
  assert.ok(Math.abs(kilometres - 111.195) < 0.001);
  assert.equal(
    greatCircleMeters({ lat: 0, lon: 0 }, { lat: 1, lon: 0 }),
    kilometres * 1000,
  );
});

test('great-circle handles dateline crossing and antipodal points', () => {
  const acrossDateline = greatCircleKm(
    { lat: 0, lon: 179 },
    { lat: 0, lon: -179 },
  );
  assert.ok(Math.abs(acrossDateline - 222.39) < 0.01);
  assert.ok(
    Math.abs(
      greatCircleKm({ lat: 0, lon: 0 }, { lat: 0, lon: 180 }) -
        Math.PI * EARTH_RADIUS_KM,
    ) < 1e-9,
  );
});

test('canonical points require explicit latitude and longitude keys', () => {
  assert.equal(isGeoPoint({ lat: 10, lon: 80 }), true);
  assert.equal(isGeoPoint({ latitude: 10, longitude: 80 }), false);
  assert.equal(isGeoPoint([10, 80]), false);
  assert.equal(
    greatCircleKm(
      { latitude: 10, longitude: 80 },
      { latitude: 20, longitude: 70 },
    ),
    Infinity,
  );
});

test('latitude-before-longitude regression rejects a swapped Austin point', () => {
  assert.ok(Number.isFinite(greatCircleKm(AUSTIN, HOUSTON)));
  assert.equal(
    greatCircleKm(
      { lat: AUSTIN.lon, lon: AUSTIN.lat },
      { lat: HOUSTON.lon, lon: HOUSTON.lat },
    ),
    Infinity,
  );
});

test('invalid, missing, non-finite, and out-of-range points return Infinity', () => {
  for (const point of [
    null,
    {},
    { lat: 0 },
    { lat: NaN, lon: 0 },
    { lat: 0, lon: Infinity },
    { lat: 90.0001, lon: 0 },
    { lat: 0, lon: -180.0001 },
  ]) {
    assert.equal(greatCircleKm(point, AUSTIN), Infinity);
    assert.equal(greatCircleMeters(AUSTIN, point), Infinity);
  }
});
