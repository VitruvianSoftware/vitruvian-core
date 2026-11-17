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
import { createShipwrecksSource } from './source.js';

const respond = (payload) =>
  createShipwrecksSource({ fetchImpl: async () => Response.json(payload) });

test('the snapshot keeps valid source ages and drops malformed ones', async () => {
  const record = { id: 'a', source: 'emodnet', lat: 50, lon: -1 };
  const good = await respond({
    records: [record],
    version: 'v',
    ages: { emodnet: 0, wikidata: 3600 },
    maxAgeMs: 604800000,
  }).getSnapshot();
  assert.deepEqual(good.ages, { emodnet: 0, wikidata: 3600 });
  assert.equal(good.maxAgeMs, 604800000);
  assert.equal(good.version, 'v');
  const bad = await respond({
    records: [record],
    ages: { emodnet: -5, wikidata: 'x' },
    maxAgeMs: Number.NaN,
  }).getSnapshot();
  assert.deepEqual(bad.ages, { emodnet: null, wikidata: null });
  assert.equal(bad.maxAgeMs, null);
  assert.equal(bad.version, null);
});
