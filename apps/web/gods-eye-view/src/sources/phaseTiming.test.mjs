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
import { createWorkTrace, recordWorkSlice } from './phaseTiming.js';

test('unsupported DEV does not create a recorder and absent recording is inert', () => {
  assert.equal(createWorkTrace(), null);
  assert.doesNotThrow(() => recordWorkSlice(null, 'unused', 0));
});

test('work intervals preserve raw endpoints and fail closed on bounded-record loss', () => {
  const trace = { slices: [], dropped: 0 };
  recordWorkSlice(trace, 'ground-step', 100, 123);
  assert.deepEqual(trace.slices[0], {
    phase: 'ground-step',
    start: 100,
    end: 123,
  });
  for (let i = 1; i <= 16; i += 1)
    recordWorkSlice(trace, 'ground-step', 200 + i, 201 + i);
  assert.equal(trace.slices.length, 16);
  assert.equal(trace.dropped, 1);
  assert.deepEqual(trace.slices[0], {
    phase: 'ground-step',
    start: 100,
    end: 123,
  });

  const detail = { index: 0, clampStart: 2, clampEnd: 3 };
  const nested = { slices: [], dropped: 0 };
  recordWorkSlice(nested, 'ground-step', 1, 4, detail);
  assert.deepEqual(nested.slices[0], {
    phase: 'ground-step',
    start: 1,
    end: 4,
    detail,
  });

  const unavailable = { slices: Object.freeze([]), dropped: 0 };
  assert.doesNotThrow(() =>
    recordWorkSlice(unavailable, 'ground-step', 1, 2, detail),
  );
  assert.equal(unavailable.dropped, 1);
});
