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

/**
 * Default landing view.
 *
 * With no share link and no host start view the globe opens over Irvine, CA:
 * controls.js defaults `startView` to HOME_START_VIEW, which is built from
 * HOME_VIEW, so changing the home city is a single-constant edit that this pin
 * verifies end to end.
 */
import assert from 'node:assert/strict';
import test from 'node:test';
import * as Cesium from 'cesium';

import { HOME_START_VIEW, HOME_VIEW, applyStartView } from './camera.js';
import { bindFakeCesiumCamera } from './testSupport/fakeCameraPort.mjs';

test('HOME_VIEW is Irvine, California', () => {
  assert.equal(HOME_VIEW.name, 'Irvine, CA');
  // Irvine city limits, roughly: 33.60–33.76 N, 117.70–117.87 W.
  assert.ok(HOME_VIEW.latitude > 33.6 && HOME_VIEW.latitude < 33.76, `lat ${HOME_VIEW.latitude}`);
  assert.ok(HOME_VIEW.longitude > -117.87 && HOME_VIEW.longitude < -117.7, `lon ${HOME_VIEW.longitude}`);
});

test('HOME_START_VIEW starts over HOME_VIEW, above the city', () => {
  assert.equal(HOME_START_VIEW.lon, HOME_VIEW.longitude);
  assert.equal(HOME_START_VIEW.lat, HOME_VIEW.latitude);
  assert.ok(HOME_START_VIEW.height > 10_000, 'high enough to see the city');
  assert.ok(HOME_START_VIEW.height < 1_000_000, 'low enough to be a city, not the planet');
});

test('applyStartView with HOME_START_VIEW sets the camera over HOME_VIEW', () => {
  const views = [];
  applyStartView(
    bindFakeCesiumCamera({
      isDestroyed: () => false,
      camera: {
        setView(view) {
          views.push(view);
        },
      },
    }),
    HOME_START_VIEW,
  );
  assert.equal(views.length, 1);
  const at = Cesium.Cartographic.fromCartesian(views[0].destination);
  assert.ok(Math.abs(Cesium.Math.toDegrees(at.longitude) - HOME_VIEW.longitude) < 1e-6);
  assert.ok(Math.abs(Cesium.Math.toDegrees(at.latitude) - HOME_VIEW.latitude) < 1e-6);
});
