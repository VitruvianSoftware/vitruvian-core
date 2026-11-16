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

// The share link's hash follows the camera through the camera port: on
// `changed` at the port's own threshold, and on `moveEnd` when it settles.
import test from 'node:test';
import assert from 'node:assert/strict';
import { ShareLinkManager } from './sharelink.js';
import { fakeCameraPort } from './testSupport/fakeCameraPort.mjs';

function setup(t) {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const written = [];
  globalThis.window = {
    location: { href: 'https://gev.example/', hash: '' },
  };
  globalThis.history = { replaceState: (_s, _t, href) => written.push(href) };
  t.after(() => {
    delete globalThis.window;
    delete globalThis.history;
  });
  const camera = fakeCameraPort({
    pose: { lon: -97.7431, lat: 30.2672, height: 600 },
  });
  const manager = new ShareLinkManager({}, { camera: camera.port });
  const lat = () => new URL(written.at(-1)).hash.match(/lat=([^&]*)/)?.[1];
  return { camera, manager, written, lat };
}

test('the hash catches up when the camera comes to rest', (t) => {
  const { camera, written, lat } = setup(t);
  camera.setPose({ lat: 30.3 });
  camera.emit('moveEnd');
  t.mock.timers.tick(500);
  assert.equal(written.length, 1);
  assert.equal(lat(), '30.3000');
});

test('the hash follows a move past the default threshold, not below it', (t) => {
  const { camera, written, lat } = setup(t);
  // The first step takes the reference view.
  camera.stepChanged();
  // A tenth of the height: below the threshold, no write.
  camera.setPose({ position: { x: 60, y: 0, z: 0 } });
  camera.stepChanged();
  t.mock.timers.tick(500);
  assert.equal(written.length, 0);
  // Past half the height: written.
  camera.setPose({ lat: 30.31, position: { x: 400, y: 0, z: 0 } });
  camera.stepChanged();
  t.mock.timers.tick(500);
  assert.equal(written.length, 1);
  assert.equal(lat(), '30.3100');
});

test('destroy lets go of both camera listeners', (t) => {
  const { camera, manager, written } = setup(t);
  assert.equal(camera.listenerCount('changed'), 1);
  assert.equal(camera.listenerCount('moveEnd'), 1);
  manager.destroy();
  assert.equal(camera.listenerCount('changed'), 0);
  assert.equal(camera.listenerCount('moveEnd'), 0);
  camera.emit('moveEnd');
  t.mock.timers.tick(500);
  assert.equal(written.length, 0);
});
