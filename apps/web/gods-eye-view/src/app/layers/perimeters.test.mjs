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
import { createApplicationFirePerimeters } from './perimeters.js';
import { bindFakeDraw } from '../../testSupport/fakeDrawPort.mjs';
import { fakeInput } from '../../input/testDoubles.mjs';

const ring = [
  [-108.1, 35.2],
  [-108.0, 35.2],
  [-108.0, 35.3],
  [-108.1, 35.2],
];
const source = {
  getSnapshot: async () => ({
    at: null,
    fetchedAt: null,
    stale: false,
    revision: 'r',
    note: null,
    fires: [{ id: 'f', name: 'Fixture', anchor: { lon: -108.05, lat: 35.25 } }],
    pieces: [{ fireId: 'f', born: null, polygons: [[ring]], outline: [ring] }],
  }),
};

for (const inciweb of [true, false]) {
  test(`inciweb: ${inciweb} ${inciweb ? 'asks' : 'never asks'} InciWeb`, async (t) => {
    const requested = [];
    t.mock.method(globalThis, 'fetch', async (url) => {
      requested.push(String(url));
      return Response.json([]);
    });
    const viewer = { scene: { pick: () => null } };
    bindFakeDraw(viewer);
    const input = fakeInput(viewer);
    t.after(() => input.destroy());
    const getIndex = t.mock.fn(async () => []);
    const layer = createApplicationFirePerimeters({
      source,
      inciweb,
      ...(inciweb === false && { inciwebSource: { getIndex } }),
      inputFor: () => input.input,
    });
    layer.init(viewer);
    layer.enable(viewer);
    assert.equal(await layer.update(viewer), true);
    await new Promise(setImmediate);
    assert.deepEqual(
      requested.filter((url) => url.includes('inciweb')),
      inciweb ? ['/api/fire-perimeters/inciweb/index'] : [],
    );
    assert.equal(getIndex.mock.callCount(), 0);
    layer.destroy(viewer);
  });
}
