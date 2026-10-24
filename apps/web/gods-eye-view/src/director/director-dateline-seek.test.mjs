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
import { cameraAtProgress } from './timeline.js';
const camera = (lon) => ({
  lat: 10,
  lon,
  alt: 1000,
  heading: 0,
  pitch: -40,
  roll: 0,
});
test('director seek follows the short dateline arc in both directions', () => {
  for (const [a, b] of [
    [179, -179],
    [-179, 179],
  ]) {
    assert.equal(
      Math.abs(cameraAtProgress(camera(a), camera(b), 0.5).lon),
      180,
    );
    assert.equal(cameraAtProgress(camera(a), camera(b), 0).lon, a);
    assert.equal(cameraAtProgress(camera(a), camera(b), 1).lon, b);
    assert.ok(Math.abs(cameraAtProgress(camera(a), camera(b), 0.25).lon) > 179);
  }
  assert.equal(cameraAtProgress(camera(20), camera(24), 0.5).lon, 22);
});

test('director seek keeps exact ±180 endpoints and picks the short arc near the antipode', () => {
  for (const [a, b] of [
    [180, -180],
    [-180, 180],
  ]) {
    assert.equal(cameraAtProgress(camera(a), camera(b), 0).lon, a);
    assert.equal(cameraAtProgress(camera(a), camera(b), 1).lon, b);
    assert.equal(
      Math.abs(cameraAtProgress(camera(a), camera(b), 0.5).lon),
      180,
    );
  }
  // 10°E to 169.9°W is 179.9° westward through Greenwich, not 180.1° east.
  const mid = cameraAtProgress(camera(10), camera(-169.9), 0.5).lon;
  assert.ok(mid > -81 && mid < -79, `short arc midpoint, got ${mid}`);
});

test('director seek turns heading and roll the short way for any authored angles', () => {
  const pose = (heading, roll) => ({ ...camera(0), heading, roll });
  const mid = cameraAtProgress(pose(350, 350), pose(-350, -350), 0.5);
  // 350° and -350° are 20° apart through 0°/360°, not 340° through 180°.
  for (const value of [mid.heading, mid.roll]) {
    const wrapped = ((value % 360) + 360) % 360;
    assert.ok(wrapped < 1e-9 || 360 - wrapped < 1e-9, `got ${value}`);
  }
});
