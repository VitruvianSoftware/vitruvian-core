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
 * With no share link the globe must open over Irvine, CA. The fly-in is a
 * two-step: an instant high setView, then a cinematic flyTo down to street
 * level. Both steps must target HOME_VIEW, so changing the home city is a
 * single-constant edit that this pin verifies end to end.
 */
import assert from 'node:assert/strict';
import test from 'node:test';
import * as Cesium from 'cesium';

import { HOME_VIEW, flyToHome } from './camera.js';

function toDegrees(cartesian) {
  const c = Cesium.Cartographic.fromCartesian(cartesian);
  return {
    longitude: Cesium.Math.toDegrees(c.longitude),
    latitude: Cesium.Math.toDegrees(c.latitude),
    height: c.height,
  };
}

function fakeViewer() {
  const calls = { setView: null, flyTo: null };
  return {
    calls,
    isDestroyed: () => false,
    camera: {
      setView(options) { calls.setView = options; },
      flyTo(options) { calls.flyTo = options; },
      cancelFlight() {},
    },
  };
}

test('HOME_VIEW is Irvine, California', () => {
  assert.equal(HOME_VIEW.name, 'Irvine, CA');
  // Irvine city limits, roughly: 33.60–33.76 N, 117.70–117.87 W.
  assert.ok(HOME_VIEW.latitude > 33.6 && HOME_VIEW.latitude < 33.76, `lat ${HOME_VIEW.latitude}`);
  assert.ok(HOME_VIEW.longitude > -117.87 && HOME_VIEW.longitude < -117.7, `lon ${HOME_VIEW.longitude}`);
});

test('flyToHome lands both fly-in steps on HOME_VIEW', async () => {
  const viewer = fakeViewer();
  flyToHome(viewer);

  assert.ok(viewer.calls.setView, 'the initial high view is set synchronously');
  const start = toDegrees(viewer.calls.setView.destination);
  assert.ok(Math.abs(start.longitude - HOME_VIEW.longitude) < 1e-6);
  assert.ok(Math.abs(start.latitude - HOME_VIEW.latitude) < 1e-6);
  assert.ok(start.height > 10_000, 'starts high so the fly-in is visible');

  assert.equal(viewer.calls.flyTo, null, 'the cinematic descent waits for the pause');
  await new Promise((resolve) => setTimeout(resolve, 700));

  assert.ok(viewer.calls.flyTo, 'the cinematic descent fires after the pause');
  const end = toDegrees(viewer.calls.flyTo.destination);
  assert.ok(Math.abs(end.longitude - HOME_VIEW.longitude) < 1e-6);
  assert.ok(Math.abs(end.latitude - HOME_VIEW.latitude) < 1e-6);
  assert.ok(end.height < start.height, 'descends toward street level');
});
