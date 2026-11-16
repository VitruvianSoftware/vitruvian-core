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
import { bindRenderer } from '../render/rendererOf.js';
import { flyToLibraryExtent } from './camera.js';

function flyingViewer(t) {
  const viewer = {};
  const flights = [];
  const unbind = bindRenderer(viewer, {
    camera: {
      flyTo(destination, options) {
        flights.push({ destination, options });
        return { done: Promise.resolve('complete'), cancel() {} };
      },
    },
  });
  t.after(unbind);
  return { viewer, flights };
}

test('Zoom to layer flies to the extent through the camera port', (t) => {
  const { viewer, flights } = flyingViewer(t);
  const extent = { west: 10, south: 50, east: 12, north: 51 };
  assert.equal(
    flyToLibraryExtent(viewer, extent, { reducedMotion: false }),
    true,
  );
  const [{ destination, options }] = flights;
  assert.equal(options.durationS, 1.6);
  // Already wide enough: the box itself.
  assert.deepEqual(destination, { rect: extent });
});

test('a view-bounded layer lands straight above its sample, below its altitude', (t) => {
  const { viewer, flights } = flyingViewer(t);
  flyToLibraryExtent(
    viewer,
    {
      west: -77.04,
      south: 38.885,
      east: -77.02,
      north: 38.9,
      maxAltitudeM: 4000,
    },
    { reducedMotion: true },
  );
  const [{ destination, options }] = flights;
  assert.equal(options.durationS, 0);
  assert.ok(Math.abs(destination.lon - -77.03) < 1e-9);
  assert.ok(Math.abs(destination.lat - 38.8925) < 1e-9);
  assert.equal(destination.height, 2400);
});

test('a world-scale layer shows the whole globe; no camera, no flight', (t) => {
  const { viewer, flights } = flyingViewer(t);
  flyToLibraryExtent(
    viewer,
    { west: -180, south: -85, east: 180, north: 85 },
    { reducedMotion: true },
  );
  assert.equal(flights[0].destination.height, 20_000_000);
  assert.equal(
    flyToLibraryExtent({}, { west: 0, south: 0, east: 1, north: 1 }),
    false,
  );
});
