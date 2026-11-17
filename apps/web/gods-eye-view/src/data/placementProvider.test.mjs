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
import { PLACEMENT_KINDS, layerPlacement } from './placementProvider.js';

test('no provider, or a provider that leaves a kind alone, gives no placement', () => {
  for (const kind of PLACEMENT_KINDS) {
    assert.equal(layerPlacement(null, kind), null);
    assert.equal(layerPlacement(undefined, kind), null);
    assert.equal(layerPlacement({ layer: () => null }, kind), null);
  }
  assert.throws(() => layerPlacement(null, 'satellites'), TypeError);
  assert.throws(() => layerPlacement({}, 'aircraft'), TypeError);
  assert.throws(
    () => layerPlacement({ layer: () => ({ observe() {} }) }, 'aircraft'),
    TypeError,
  );
});

test('a placement is asked by id and wall time, and its answer is checked', () => {
  const asked = [];
  const seen = [];
  const forgotten = [];
  const answers = new Map([
    [
      'a',
      { lat: 51.5, lon: -0.1, altitudeM: 900, courseDeg: 270, speedMps: 80 },
    ],
    ['partial', { lat: 10, lon: 20, altitudeM: 'high', extrapolating: true }],
    ['off-globe', { lat: 91, lon: 0 }],
    ['nan', { lat: NaN, lon: 0 }],
  ]);
  const provider = {
    layer: (kind) =>
      kind === 'aircraft'
        ? {
            observe: (id, fix) => seen.push([id, fix.timeMs]),
            place(id, wallMs) {
              asked.push([id, wallMs]);
              return answers.get(id) ?? null;
            },
            forget: (id) => forgotten.push(id),
          }
        : null,
  };
  assert.equal(layerPlacement(provider, 'vessels'), null);
  const placement = layerPlacement(provider, 'aircraft');
  placement.observe('a', { timeMs: 5, lat: 0, lon: 0 });
  assert.deepEqual(seen, [['a', 5]]);
  const placed = placement.place('a', 1000);
  assert.deepEqual(
    { ...placed },
    {
      lat: 51.5,
      lon: -0.1,
      altitudeM: 900,
      courseDeg: 270,
      speedMps: 80,
      extrapolating: false,
    },
  );
  const partial = placement.place('partial', 2000);
  assert.equal(partial, placed, 'one answer object, reused');
  assert.ok(Number.isNaN(partial.altitudeM));
  assert.ok(Number.isNaN(partial.courseDeg));
  assert.ok(Number.isNaN(partial.speedMps));
  assert.equal(partial.extrapolating, true);
  assert.equal(placement.place('off-globe', 3000), null);
  assert.equal(placement.place('nan', 3000), null);
  assert.equal(placement.place('unknown', 3000), null);
  assert.deepEqual(
    asked.map(([id]) => id),
    ['a', 'partial', 'off-globe', 'nan', 'unknown'],
  );
  placement.forget('a');
  assert.deepEqual(forgotten, ['a']);
});

test('a provider that throws has no answer, and observe and forget are optional', () => {
  const placement = layerPlacement(
    {
      layer: () => ({
        place() {
          throw new Error('not ready');
        },
      }),
    },
    'transit',
  );
  assert.equal(placement.place('x', 0), null);
  assert.doesNotThrow(() => placement.observe('x', { timeMs: 0 }));
  assert.doesNotThrow(() => placement.forget('x'));
  const failing = layerPlacement(
    {
      layer: () => ({
        place: () => null,
        observe() {
          throw new Error('full');
        },
        forget() {
          throw new Error('gone');
        },
      }),
    },
    'rail',
  );
  assert.doesNotThrow(() => failing.observe('x', { timeMs: 0 }));
  assert.doesNotThrow(() => failing.forget('x'));
});
