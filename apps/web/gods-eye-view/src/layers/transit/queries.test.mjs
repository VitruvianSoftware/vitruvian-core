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
import { createQueries } from './queries.js';
import { TRANSIT_ENABLED_FEEDS } from '../../data/transitFeeds.js';

test('the empty-coverage note counts regions, not feeds', () => {
  const rio = TRANSIT_ENABLED_FEEDS.filter(
    (feed) => feed.region === 'Rio de Janeiro, RJ',
  );
  assert.equal(rio.length, 2, 'Rio is one region with two feeds');
  const regions = new Set(TRANSIT_ENABLED_FEEDS.map((feed) => feed.region));
  assert.ok(regions.size < TRANSIT_ENABLED_FEEDS.length);

  const stats = createQueries({
    state: {
      _activeFeeds: new Map(),
      _vehicles: new Map(),
      _enabled: true,
      _altitudeGateOpen: true,
    },
    parts: {},
  }).methods.getStats();
  assert.equal(stats.status, 'zoom-in');
  assert.equal(
    stats.coverage,
    `No feed here yet · ${regions.size} regions available`,
  );
});
