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

// src/layers/flights/rendering.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { createRendering as createFlightsRendering } from './rendering.js';
import { createRendering as createMilitaryRendering } from '../military/rendering.js';

function rendering(create) {
  const data = new Map([
    ['light', { klass: 'light' }],
    ['quadjet', { klass: 'quadjet' }],
    ['vehicle', { klass: 'vehicle' }],
    ['parked', { klass: 'quadjet', onGround: true }],
  ]);
  return create({
    flightState: { records: { data } },
    services: {
      militaryRegistry: { isMilitaryIcao: () => false },
      aircraftPresentation: { tr3bIconKind: () => null },
      focus: { focusNowMs: () => 0, getFocusTarget: () => null },
    },
    parts: {},
    layer: {},
    resolveAsset: (url) => url,
  });
}

test('Flights draws every class at one size, smaller on the ground', () => {
  const r = rendering(createFlightsRendering);
  for (const id of ['light', 'quadjet', 'vehicle']) {
    assert.equal(r._fleetBillboardScale(id), 1, id);
  }
  assert.equal(r._fleetBillboardScale('parked'), 0.8);
});

test('Military draws every class at its one size, smaller on the ground', () => {
  const r = rendering(createMilitaryRendering);
  const size = r._fleetBillboardScale('light');
  for (const id of ['quadjet', 'vehicle']) {
    assert.equal(r._fleetBillboardScale(id), size, id);
  }
  assert.ok(Math.abs(r._fleetBillboardScale('parked') - size * 0.8) < 1e-12);
});
