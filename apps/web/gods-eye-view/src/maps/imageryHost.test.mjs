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
import { NO_IMAGERY_HOST, resolveImageryHost } from './imageryHost.js';

test('a shown globe hosts imagery on the viewer collection', () => {
  const imageryLayers = { id: 'globe' };
  const host = resolveImageryHost({
    viewer: { scene: { globe: { show: true } }, imageryLayers },
    tileset: { imageryLayers: { id: 'tiles' } },
  });
  assert.deepEqual(host, { collection: imageryLayers, kind: 'globe' });
});

test('a hidden globe hands imagery to the tileset collection', () => {
  const imageryLayers = { id: 'tiles' };
  const host = resolveImageryHost({
    viewer: { scene: { globe: { show: false } }, imageryLayers: {} },
    tileset: { imageryLayers, isDestroyed: () => false },
  });
  assert.deepEqual(host, { collection: imageryLayers, kind: 'tileset' });
});

test('no globe and no tileset means nowhere to drape', () => {
  assert.deepEqual(
    resolveImageryHost({
      viewer: { scene: { globe: { show: false } }, imageryLayers: {} },
      tileset: null,
    }),
    { collection: null, kind: 'none' },
  );
  assert.deepEqual(resolveImageryHost({}), { collection: null, kind: 'none' });
  assert.deepEqual(
    resolveImageryHost({
      viewer: { scene: { globe: { show: false } } },
      tileset: { imageryLayers: {}, isDestroyed: () => true },
    }),
    { collection: null, kind: 'none' },
  );
  assert.match(NO_IMAGERY_HOST, /globe map/);
});
