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

// A layer disable asks for one frame and has the renderer trim what it no
// longer draws once that frame is drawn (src/sceneCommandRelease.js).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { installLayerReleaseTrim } from './sceneCommandRelease.js';

test('a layer disable renders one frame and trims after it', () => {
  const listeners = new Set();
  const postRender = new Set();
  const requests = [];
  let trims = 0;
  const uninstall = installLayerReleaseTrim({
    frame: {
      on(phase, fn) {
        assert.equal(phase, 'postRender');
        postRender.add(fn);
        return () => postRender.delete(fn);
      },
    },
    dataManager: {
      subscribe(fn) {
        listeners.add(fn);
        return () => listeners.delete(fn);
      },
    },
    requestRender: (reason) => requests.push(reason),
    trim: () => (trims += 1),
  });
  const emit = (change) => listeners.forEach((fn) => fn(change));

  emit({ type: 'visibility', layerId: 'x', enabled: true });
  assert.equal(requests.length, 0, 'enabling trims nothing');
  emit({ type: 'visibility', layerId: 'x', enabled: false });
  emit({ type: 'visibility', layerId: 'y', enabled: false });
  assert.deepEqual(
    requests,
    ['layer-release-trim'],
    'one frame for back-to-back disables',
  );
  assert.equal(trims, 0, 'not before the frame');
  postRender.forEach((fn) => fn());
  assert.equal(trims, 1);
  assert.equal(postRender.size, 0, 'the frame listener is one-shot');
  emit({ type: 'visibility', layerId: 'z', enabled: false });
  assert.equal(postRender.size, 1);
  uninstall();
  assert.equal(listeners.size, 0);
  assert.equal(postRender.size, 0, 'a waiting trim goes with it');
});

test('on the frame port the trim runs once, after the frame, beside other listeners', async () => {
  const { listenerList } = await import('./render/cesium/common.js');
  const postRender = listenerList((error) => {
    throw error;
  });
  const seen = [];
  postRender.on(() => seen.push('before'));
  let emit;
  const uninstall = installLayerReleaseTrim({
    frame: { on: (phase, cb) => postRender.on(cb) },
    dataManager: {
      subscribe(fn) {
        emit = fn;
        return () => {};
      },
    },
    requestRender() {},
    trim: () => seen.push('trim'),
  });
  emit({ type: 'visibility', enabled: false });
  postRender.on(() => seen.push('after'));
  postRender.fire();
  postRender.fire();
  assert.deepEqual(seen, ['before', 'trim', 'after', 'before', 'after']);
  assert.equal(postRender.size, 2);
  uninstall();
});
