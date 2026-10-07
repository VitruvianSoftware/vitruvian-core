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
import { createPickRouter } from './pickRouter.js';

const providers = [
  { def: { id: 'mapillary', pickPrefix: 'mly:' }, instance: { name: 'm' } },
  { def: { id: 'panoramax', pickPrefix: 'pnx:' }, instance: { name: 'p' } },
];

test('ids are routed by prefix to their provider instance', () => {
  const router = createPickRouter(() => providers, { positionId: 'sl:pos' });
  assert.deepEqual(router.resolve('mly:seq:1'), {
    providerId: 'mapillary',
    instance: providers[0].instance,
    id: 'mly:seq:1',
  });
  assert.equal(router.resolve('pnx:img:9').providerId, 'panoramax');
  assert.equal(router.ownsPick('mly:img:2'), true);
});

test('the core-owned marker is owned but routes to no provider', () => {
  const router = createPickRouter(() => providers, { positionId: 'sl:pos' });
  assert.deepEqual(router.resolve('sl:pos'), {
    providerId: null,
    instance: null,
    id: 'sl:pos',
  });
  assert.equal(router.ownsPick('sl:pos'), true);
});

test('foreign and malformed ids are not ours', () => {
  const router = createPickRouter(() => providers);
  for (const id of ['cctv:1', '', null, undefined, 42, {}])
    assert.equal(router.ownsPick(id), false, String(id));
  assert.equal(router.resolve('sl:pos'), null, 'no marker id configured');
});
