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
import { nextCockpitNearContacts } from './cockpitAirLod.js';

test('Cockpit AIR LOD admits at ADD and retains through KEEP', () => {
  const previous = new Set(['retained', 'expired']);
  const next = nextCockpitNearContacts(previous, [
    ['new-near', 149_000 ** 2],
    ['new-outside-add', 151_000 ** 2],
    ['retained', 184_000 ** 2],
    ['expired', 186_000 ** 2],
  ], 150_000, 185_000);

  assert.deepEqual([...next].sort(), ['new-near', 'retained']);
});

test('Cockpit AIR LOD switches to the All range without a model-budget dependency', () => {
  const next = nextCockpitNearContacts(new Set(), [
    ['inside-all', 399_000 ** 2],
    ['outside-all', 401_000 ** 2],
  ], 400_000, 450_000);

  assert.deepEqual([...next], ['inside-all']);
});

test('Cockpit AIR LOD drops absent and invalid contacts', () => {
  const next = nextCockpitNearContacts(new Set(['gone']), [
    ['nan', Number.NaN],
    ['', 1],
  ], 150_000, 185_000);

  assert.equal(next.size, 0);
});

