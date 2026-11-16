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
import { bindRenderer } from '../../render/rendererOf.js';
import { createController } from './controller.js';

const controller = () =>
  createController({ flightState: { feed: {} }, parts: {}, layer: {} });

test('the feed is asked for the flights around the camera port’s ground point', () => {
  let pose = { lon: -97.04, lat: 32.9, height: 9000 };
  const viewer = {};
  const unbind = bindRenderer(viewer, { camera: { pose: () => pose } });
  try {
    const { _flightQuery } = controller();
    assert.deepEqual(_flightQuery(viewer), {
      latitude: 32.9,
      longitude: -97.04,
    });
    pose = { lon: NaN, lat: NaN, height: NaN };
    assert.deepEqual(_flightQuery(viewer), {}, 'no ground point: no area');
    pose = { lon: -97.04, lat: NaN, height: 9000 };
    assert.deepEqual(_flightQuery(viewer), {}, 'half a ground point: none');
  } finally {
    unbind();
  }
});

test('with no viewer or camera the query names no area', () => {
  const { _flightQuery } = controller();
  assert.deepEqual(_flightQuery(null), {});
  assert.deepEqual(_flightQuery(undefined), {});
  assert.deepEqual(_flightQuery({}), {}, 'a viewer with no camera');
  assert.deepEqual(
    _flightQuery({ isDestroyed: () => true, camera: {} }),
    {},
    'a destroyed viewer',
  );
});
