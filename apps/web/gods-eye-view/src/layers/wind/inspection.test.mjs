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
  windFrom,
  formatWindSpeed,
  inspectWindAtCenter,
} from './inspection.js';

test('wind directions describe the source of the flow and calm is not north', () => {
  assert.equal(windFrom(10, 0), 'W');
  assert.equal(windFrom(-10, 0), 'E');
  assert.equal(windFrom(0, 10), 'S');
  assert.equal(windFrom(0, -10), 'N');
  assert.equal(windFrom(0, 0), 'Calm');
  assert.equal(formatWindSpeed(10, 'km/h'), '36.0 km/h');
  assert.equal(formatWindSpeed(10, 'mph'), '22.4 mph');
});
test('center inspection uses a fixed forecast reading without double-converting scalar units', () => {
  const snapshot = {
    grid: { nx: 2, ny: 2, lo1: 0, la1: 90, dx: 180, dy: 180 },
    u: Float32Array.from([10, 10, 10, 10]),
    v: new Float32Array(4),
    scalar: {
      kind: 'temperature',
      units: '°C',
      values: Float32Array.from([20, 20, 20, 20]),
    },
  };
  const viewer = {
    camera: { pickEllipsoid: () => ({ longitude: 0, latitude: 0 }) },
    scene: { canvas: { clientWidth: 800, clientHeight: 600 } },
  };
  const cesium = {
    Cartesian2: class {
      constructor(x, y) {
        this.x = x;
        this.y = y;
      }
    },
    Ellipsoid: { WGS84: {} },
    Cartographic: { fromCartesian: (p) => p },
    Math: { toDegrees: (x) => (x * 180) / Math.PI },
  };
  const result = inspectWindAtCenter(snapshot, viewer, cesium, {
    overlay: 'temperature',
    units: 'km/h',
    model: 'GFS',
    validTime: 'fixed',
    status: 'forecast',
  });
  assert.equal(result.wind, '36.0 km/h from W');
  assert.equal(result.scalarValue, '20.0 °C');
  assert.equal(result.validTime, 'fixed');
  assert.equal(result.coordinates, '0.00°N · 0.00°E');
  viewer.camera.pickEllipsoid = () => null;
  assert.equal(
    inspectWindAtCenter(snapshot, viewer, cesium).coordinates,
    'No surface reading',
  );
});
