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

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { isCalibratedAllocationRuntime } from '../../scripts/run-unit-tests.mjs';

/**
 * Allocation budgets cover two intentionally different call shapes:
 * - Prebuilt-option pure paths: <=16 B/call for each treatment helper.
 * - Production sprite tick: <=212 B/tick when its caller builds both fresh
 *   options literals. The latter preserves roughly 25% headroom over the
 *   locally measured steady-state median instead of pretending those caller
 *   allocations belong to the pure helper bound.
 */
test('converged focus treatment stays within the GC-bracketed allocation budget', (t) => {
  if (!isCalibratedAllocationRuntime()) {
    return t.skip(`allocation budgets are calibrated for Node 24; running ${process.versions.node}`);
  }
  const result = spawnSync(
    process.execPath,
    ['--expose-gc', 'scripts/focus-allocation-check.mjs'],
    { cwd: process.cwd(), encoding: 'utf8' },
  );
  assert.equal(result.status, 0, result.stderr || result.stdout);
  const report = JSON.parse(result.stdout.trim());
  assert.ok(report.advanceSpriteFocus.roundedMedian <= 16, result.stdout);
  assert.ok(report.applyAircraftBillboardTreatment.roundedMedian <= 16, result.stdout);
  assert.ok(report.productionSpriteTick.roundedMedian <= 212, result.stdout);
});
