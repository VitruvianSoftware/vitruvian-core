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
import { bindRenderer } from '../../render/rendererOf.js';
import { createStubRenderer } from '../../render/stub/index.js';

test('only a missing host suspends weather; 3D Tiles has no height gate', () => {
  assert.equal(imageryHostStatus({ kind: 'tileset' }), null);
  assert.equal(imageryHostStatus({ kind: 'globe' }), null);
  assert.equal(imageryHostStatus({ kind: 'none' }), NO_IMAGERY_HOST);
});

test('weather drapes on the map stack imagery host', () => {
  const renderer = createStubRenderer();
  const viewer = {};
  bindRenderer(viewer, renderer);
  const tileset = { id: 'tiles' };
  assert.deepEqual(resolveImageryHost({ viewer, tileset }), {
    collection: renderer.globe.imagery,
    kind: 'globe',
  });
  renderer.globe.setGlobeVisible(false);
  assert.deepEqual(resolveImageryHost({ viewer, tileset }), {
    collection: tileset,
    kind: 'tileset',
  });
  assert.deepEqual(resolveImageryHost({ viewer, tileset: null }), {
    collection: null,
    kind: 'none',
  });
});
