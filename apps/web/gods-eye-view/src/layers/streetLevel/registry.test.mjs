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
import { requiresKeyIdFor, validateProviders } from './registry.js';

const def = (overrides = {}) => ({
  id: 'mapillary',
  name: 'Mapillary',
  label: 'MAPILLARY',
  requiresKeyId: 'mapillary',
  pickPrefix: 'mly:',
  colors: { coverage: '#05cb63' },
  credit: { html: 'Mapillary' },
  create: () => ({}),
  ...overrides,
});

test('a valid list is frozen in registration order', () => {
  const list = validateProviders([
    def(),
    def({ id: 'panoramax', pickPrefix: 'pnx:', requiresKeyId: null }),
  ]);
  assert.ok(Object.isFrozen(list));
  assert.deepEqual(
    list.map((p) => p.id),
    ['mapillary', 'panoramax'],
  );
});

test('an empty list, duplicate ids and malformed ids are rejected', () => {
  assert.throws(() => validateProviders([]), /at least one/);
  assert.throws(() => validateProviders(null), /at least one/);
  assert.throws(() => validateProviders([def(), def()]), /Duplicate/);
  assert.throws(() => validateProviders([def({ id: 'Bad Id' })]), /slug/);
});

test('every required field is checked by name', () => {
  for (const key of [
    'name',
    'label',
    'pickPrefix',
    'colors',
    'credit',
    'create',
  ])
    assert.throws(
      () => validateProviders([def({ [key]: undefined })]),
      new RegExp(`lacks ${key}`),
      key,
    );
  assert.throws(() => validateProviders([def({ create: 1 })]), /create/);
  assert.throws(() => validateProviders([def({ credit: {} })]), /credit/);
  assert.throws(
    () => validateProviders([def({ colors: { pano: '#f0f' } })]),
    /coverage colour/,
  );
  assert.throws(
    () => validateProviders([def({ pickPrefix: '' })]),
    /pick prefix/,
  );
});

test('overlapping pick prefixes are rejected either way round', () => {
  assert.throws(
    () => validateProviders([def(), def({ id: 'other', pickPrefix: 'mly:x' })]),
    /overlaps/,
  );
  assert.throws(
    () =>
      validateProviders([def({ pickPrefix: 'mly:x' }), def({ id: 'other' })]),
    /overlaps/,
  );
  assert.doesNotThrow(() =>
    validateProviders([def(), def({ id: 'other', pickPrefix: 'ml:' })]),
  );
});

test('requiresKeyIdFor is the shared key, or null once providers differ', () => {
  assert.equal(requiresKeyIdFor([def()]), 'mapillary');
  assert.equal(
    requiresKeyIdFor([def(), def({ id: 'b', pickPrefix: 'b:' })]),
    'mapillary',
  );
  assert.equal(
    requiresKeyIdFor([
      def(),
      def({ id: 'b', pickPrefix: 'b:', requiresKeyId: null }),
    ]),
    null,
  );
  assert.equal(
    requiresKeyIdFor([
      def(),
      def({ id: 'b', pickPrefix: 'b:', requiresKeyId: 'google-maps' }),
    ]),
    null,
  );
  assert.equal(requiresKeyIdFor([def({ requiresKeyId: null })]), null);
});
