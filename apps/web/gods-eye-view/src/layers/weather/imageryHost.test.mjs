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
import {
  resolveImageryHost,
  imageryHostStatus,
  NO_IMAGERY_HOST,
} from './imageryHost.js';

test('only a missing host suspends weather; 3D Tiles has no height gate', () => {
  assert.equal(imageryHostStatus({ kind: 'tileset' }), null);
  assert.equal(imageryHostStatus({ kind: 'globe' }), null);
  assert.equal(imageryHostStatus({ kind: 'none' }), NO_IMAGERY_HOST);
});

test('visible globe takes precedence over a tileset', () => {
  const viewer = { imageryLayers: {}, scene: { globe: { show: true } } };
  assert.deepEqual(
    resolveImageryHost({ viewer, tileset: { imageryLayers: {} } }),
    { collection: viewer.imageryLayers, kind: 'globe' },
  );
});
test('hidden globe uses the supplied tileset imagery collection', () => {
  const tileset = { imageryLayers: {} };
  const viewer = { scene: { globe: { show: false } } };
  assert.deepEqual(resolveImageryHost({ viewer, tileset }), {
    collection: tileset.imageryLayers,
    kind: 'tileset',
  });
});
test('hidden globe without an imagery-capable tileset has no host', () => {
  for (const tileset of [null, {}])
    assert.deepEqual(
      resolveImageryHost({
        viewer: { scene: { globe: { show: false } } },
        tileset,
      }),
      { collection: null, kind: 'none' },
    );
});
