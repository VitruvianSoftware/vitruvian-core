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

// src/ui/placePacksLoading.test.mjs — the loading status names the place
// packs while they load, and a failed pack ends the batch as failed.
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  aggregateLayerLoading,
  createLoadingFeedbackState,
  reduceLoadingFeedback,
} from '../loadingFeedback.js';
import { withPlacePacks } from './placePacksLoading.js';

const SATELLITES = Object.freeze({
  id: 'satellites',
  name: 'Satellites',
  enabled: true,
  stats: { count: 9000, lastUpdate: 1 },
});

function batch(states) {
  let state = createLoadingFeedbackState();
  let now = 0;
  for (const status of states) {
    now += 1000;
    state = reduceLoadingFeedback(
      state,
      aggregateLayerLoading(withPlacePacks([SATELLITES], status)),
      now,
    );
  }
  return state;
}

test('nothing extra while the packs are idle', () => {
  const layers = [SATELLITES];
  assert.equal(
    withPlacePacks(layers, { loading: false, failed: false }),
    layers,
  );
});

test('the packs are named while they load', () => {
  const summary = aggregateLayerLoading(
    withPlacePacks([SATELLITES], { loading: true, failed: false }),
  );
  assert.deepEqual(summary.activeIds, ['place-names']);
  assert.equal(summary.active[0].label, 'Place names');
});

test('a load that lands ends complete; one that fails ends failed', () => {
  const loading = { loading: true, failed: false };
  assert.equal(
    batch([loading, { loading: false, failed: false }]).terminal,
    'complete',
  );
  assert.equal(
    batch([loading, { loading: false, failed: true }]).terminal,
    'error',
  );
  // A retry after a failure that lands ends complete.
  assert.equal(
    batch([
      { loading: false, failed: true },
      loading,
      { loading: false, failed: false },
    ]).terminal,
    'complete',
  );
});
