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
import { installationFeedback } from './installationFeedback.js';

test('retry copy follows the real deadline and does not promise an overdue timer fired', () => {
  assert.equal(installationFeedback({ retryAt: 31000 }, 1000), 'Overpass temporarily unavailable — retrying in 30s');
  assert.match(installationFeedback({ retryAt: 31000 }, 32000), /retry pending$/);
  assert.match(installationFeedback({ retryAt: 241000 }, 1000), /240s$/);
});
test('only known failure reasons get specific attribution', () => {
  for (const [failureReason, text] of [['rate_limited', 'rate-limited'], ['timeout', 'timed out'], ['query_failed', 'could not complete']]) {
    assert.ok(installationFeedback({ status: 'unavailable', failureReason }).includes(text));
  }
  assert.match(installationFeedback({ status: 'unavailable', failureReason: 'unknown' }), /temporarily unavailable/);
});
test('first fetch, retry, cached data and success have distinct copy', () => {
  assert.equal(installationFeedback({ loading: true }), 'Fetching mapped sites…');
  assert.equal(installationFeedback({ loading: true, retrying: true }), 'Retrying mapped sites…');
  assert.equal(installationFeedback({ status: 'ready' }), 'Mapped sites loaded');
  assert.equal(installationFeedback({ stale: true }), 'Showing cached mapped sites');
});
