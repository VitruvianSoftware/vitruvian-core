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
import { MapSourceController } from './controller.js';
function fixture() {
  return new MapSourceController(
    {
      scene: {
        globe: { show: true },
        requestRender() {},
        frameState: {
          creditDisplay: { addStaticCredit() {}, removeStaticCredit() {} },
        },
        primitives: { add() {}, remove() {} },
      },
      imageryLayers: { add() {}, remove() {} },
    },
    {
      registry: {
        defaultId: 'fixture',
        sources: [
          {
            descriptor: { id: 'fixture', label: 'Fixture', kind: 'imagery' },
            imagery: async () => ({}),
          },
        ],
      },
      createImageryLayer: (provider) => ({ provider }),
    },
  );
}
test('an unsubscribed owner is skipped in the same map settlement delivery', async () => {
  const controller = fixture();
  const calls = [];
  let detach;
  controller.subscribe(() => {
    calls.push('first');
    detach();
  });
  detach = controller.subscribe(() => calls.push('detached'));
  controller.subscribe(() => calls.push('last'));
  await controller.setStack('fixture');
  assert.deepEqual(calls, ['first', 'last']);
  controller.destroy();
});
test('destroying the controller during delivery stops remaining listeners', async () => {
  const controller = fixture();
  const calls = [];
  controller.subscribe(() => {
    calls.push('destroy');
    controller.destroy();
  });
  controller.subscribe(() => calls.push('detached'));
  await controller.setStack('fixture');
  assert.deepEqual(calls, ['destroy']);
});

test('a listener re-added after destroy during delivery is not called', async () => {
  const controller = fixture();
  const calls = [];
  const later = () => calls.push('later');
  controller.subscribe(() => {
    calls.push('destroy');
    controller.destroy();
    controller.subscribe(later);
  });
  controller.subscribe(later);
  await controller.setStack('fixture');
  assert.deepEqual(calls, ['destroy']);
});

test('delivery order: added during delivery waits, duplicates run once, re-added runs', async () => {
  const controller = fixture();
  const calls = [];
  const twice = () => calls.push('twice');
  const readded = () => calls.push('readded');
  let offReadded;
  controller.subscribe(() => {
    calls.push('first');
    controller.subscribe(() => calls.push('added-late'));
    offReadded();
    controller.subscribe(readded);
  });
  controller.subscribe(twice);
  controller.subscribe(twice);
  offReadded = controller.subscribe(readded);
  await controller.setStack('fixture');
  assert.deepEqual(calls, ['first', 'twice', 'readded']);
  controller.destroy();
});
