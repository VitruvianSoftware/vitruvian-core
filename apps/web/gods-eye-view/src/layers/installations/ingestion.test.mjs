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
import { createIngestion } from './ingestion.js';

// Taveuni, Fiji: Cesium reports a view across 180° with west > east. Each view
// is 0.4° wide and 0.2° tall; the last one does not cross 180°.
for (const [west, east, centre] of [
  [179.7, -179.9, 179.9],
  [179.9, -179.7, -179.9],
  [179.5, 179.9, 179.7],
])
  test(`a nearby search is centred on the view at ${centre}`, async () => {
    const box = { south: -17, west, north: -16.8, east };
    const searches = [];
    const state = {
      enabled: true,
      viewer: {},
      records: [],
      googleSearchRequested: true,
    };
    const ingestion = createIngestion({
      state,
      source: {
        getMappedSites: async () => ({ records: [], wide: true }),
        searchNearby: async (query) => {
          searches.push(query);
          return { places: [] };
        },
      },
      services: {
        render: { governorRequestRender() {} },
        ground: { resolveGroundFloorCellsBounded: async () => {} },
      },
      parts: {
        viewport: {
          loadArea: () => ({ box, coverage: {} }),
          clearUnavailableRetry() {},
          scheduleUnavailableRetry() {},
        },
        model: { installationWithinViewport: () => true },
        rendering: { renderRecords() {}, warmInstallationFloors() {} },
      },
    });
    await ingestion.loadInstallations();
    assert.equal(searches.length, 1);
    const { latitude, longitude, radiusM } = searches[0];
    assert.ok(Math.abs(latitude + 16.9) < 1e-9);
    assert.ok(Math.abs(longitude - centre) < 1e-9, `longitude ${longitude}`);
    // The width, not the height, sets the radius.
    assert.equal(radiusM, 22000);
  });
