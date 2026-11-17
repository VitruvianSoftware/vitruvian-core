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
import { StyleManager } from './applicationShell.js';

test('an unavailable map stack reports the controller’s own reason, not always an ion token', async () => {
  const controller = {
    getStacks: () => [
      {
        id: 'photoreal',
        label: 'Google 3D',
        available: false,
        unavailableReason: 'Google 3D needs GOOGLE_MAPS_API_KEY',
      },
      { id: 'bing-aerial', label: 'Bing aerial', available: false },
    ],
    getActiveId: () => 'osm',
  };
  const shell = { mapStackController: controller };
  const photoreal = await StyleManager.prototype.setMapStack.call(
    shell,
    'photoreal',
  );
  assert.deepEqual(photoreal, {
    ok: false,
    error: 'Google 3D needs GOOGLE_MAPS_API_KEY',
    activeStack: 'osm',
  });
  const bing = await StyleManager.prototype.setMapStack.call(
    shell,
    'bing-aerial',
  );
  assert.equal(bing.error, 'Bing aerial requires a Cesium ion token');
});
