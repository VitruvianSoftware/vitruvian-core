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
import * as Cesium from 'cesium';
import { bindFakeCesiumCamera } from '../testSupport/fakeCameraPort.mjs';
import { rangeForBoundingSphere } from './cameraFraming.js';

/** The range as it was read from Cesium's frustum before the camera port. */
function rangeFromFrustum(frustum, radius) {
  const verticalFov = frustum.fov;
  const aspectRatio = Math.max(0.5, frustum.aspectRatio);
  const horizontalFov = 2 * Math.atan(Math.tan(verticalFov / 2) * aspectRatio);
  const limitingFov = Math.min(verticalFov, horizontalFov);
  return (radius / Math.sin((limitingFov * 0.57) / 2)) * 1.05;
}

for (const aspectRatio of [16 / 9, 390 / 844, 1]) {
  test(`framing reads the frustum's field of view through the camera port (aspect ${aspectRatio.toFixed(2)})`, () => {
    const frustum = new Cesium.PerspectiveFrustum({
      fov: Math.PI / 3,
      aspectRatio,
      near: 1,
      far: 1e8,
    });
    const viewer = bindFakeCesiumCamera({ camera: { frustum } });
    const range = rangeForBoundingSphere(viewer, 250);
    assert.ok(
      Math.abs(range - rangeFromFrustum(frustum, 250)) < 1e-6,
      `${range} vs ${rangeFromFrustum(frustum, 250)}`,
    );
  });
}

test('framing without a camera assumes a 60 degree square view', () => {
  const expected = rangeFromFrustum({ fov: Math.PI / 3, aspectRatio: 1 }, 100);
  assert.ok(Math.abs(rangeForBoundingSphere({}, 100) - expected) < 1e-9);
});
