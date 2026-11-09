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
import { performance } from 'node:perf_hooks';
import test from 'node:test';
import { perfBudgetTestOptions } from '../../../scripts/run-perf-tests.mjs';
import {
  harness,
  syntheticRows,
  changePositions,
  WILDLIFE_BENCHMARK_REFRESHES,
} from '../../testSupport/wildlifeBillboardModel.mjs';

// Pure model and incremental reconciliation, measured after warmup.
// The 2,000-contact allowance is a fraction of one 60Hz frame; the 5,000 cap
// gets a proportional allowance. No renderer, network or real sightings run.
const WILDLIFE_MODEL_UPDATE_BUDGET_MS = Object.freeze({
  500: 4,
  2000: 8,
  5000: 20,
});
test(
  '500 / 2,000 / 5,000 icon model updates stay within their named timing budgets',
  perfBudgetTestOptions(),
  (t) => {
    // Warm the same pure hot paths before recording CPU time.
    const warm = harness();
    let warmRows = syntheticRows(2000);
    warm.apply(warmRows);
    for (let i = 0; i < 25; i++) {
      warmRows = changePositions(warmRows, i);
      warm.apply(warmRows);
    }
    for (const n of [500, 2000, 5000]) {
      const h = harness();
      let rows = syntheticRows(n);
      const start = performance.now();
      const initial = h.apply(rows);
      const initialMs = performance.now() - start;
      assert.equal(initial.created, n);
      const durations = [];
      for (let refresh = 0; refresh < WILDLIFE_BENCHMARK_REFRESHES; refresh++) {
        rows = changePositions(rows, refresh);
        const before = performance.now();
        const update = h.apply(rows);
        durations.push(performance.now() - before);
        assert.deepEqual(update, {
          created: 0,
          removed: 0,
          updated: n / 10,
          writes: n / 10,
        });
      }
      const meanMs =
        durations.reduce((sum, value) => sum + value, 0) / durations.length;
      const maxMs = Math.max(...durations);
      assert.ok(
        maxMs <= WILDLIFE_MODEL_UPDATE_BUDGET_MS[n],
        `${n}: ${maxMs.toFixed(3)}ms update exceeds ${WILDLIFE_MODEL_UPDATE_BUDGET_MS[n]}ms`,
      );
      const before = { ...h.counters };
      assert.deepEqual(h.apply([...rows].reverse()), {
        created: 0,
        removed: 0,
        updated: 0,
        writes: 0,
      });
      assert.deepEqual(
        h.counters,
        before,
        'unchanged content performs zero billboard writes or allocations',
      );
      t.diagnostic(
        `N=${n}; initial=${initialMs.toFixed(3)}ms; incremental10% mean=${meanMs.toFixed(3)}ms, max=${maxMs.toFixed(3)}ms; budget=${WILDLIFE_MODEL_UPDATE_BUDGET_MS[n]}ms; unchanged writes=0`,
      );
    }
  },
);
