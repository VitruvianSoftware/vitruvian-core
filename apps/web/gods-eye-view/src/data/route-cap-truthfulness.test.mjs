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
import { normalizeOsrmSteps, ROUTE_STEPS_MAX } from './routeSteps.js';
const step = (type) => ({
  maneuver: { type, location: [10, 20] },
  distance: 10,
  duration: 1,
});
test('exact-cap routes remain complete and boundary exits retain their distance', () => {
  const steps = Array.from({ length: ROUTE_STEPS_MAX }, () => step('turn'));
  assert.equal(normalizeOsrmSteps({ legs: [{ steps }] }).truncated, false);
  assert.equal(
    normalizeOsrmSteps({ legs: [{ steps: [...steps, step('turn')] }] })
      .truncated,
    true,
  );
  steps[steps.length - 1] = step('roundabout');
  const result = normalizeOsrmSteps({
    legs: [{ steps: [...steps, step('exit roundabout')] }],
  });
  assert.equal(result.truncated, false);
  assert.equal(result.steps.length, ROUTE_STEPS_MAX);
  assert.equal(result.steps.at(-1).distanceM, 20);
});
