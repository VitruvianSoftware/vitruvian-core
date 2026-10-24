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
import { acquisitionMsUtc } from './firmsCsv.js';
test('FIRMS acquisition dates cannot roll into a different calendar day', () => {
  for (const [date, time] of [
    ['2026-02-30', '1200'],
    ['2026-04-31', '1200'],
    ['2026-13-01', '1200'],
    ['2026-07-16junk', '1200'],
    ['2026-07-16', '2400'],
    ['2026-07-16', '1260'],
    ['2026-07-16', null],
    ['2026-07-16', ''],
  ]) {
    assert.ok(Number.isNaN(acquisitionMsUtc(date, time)), `${date}:${time}`);
  }
  for (const [date, time, expected] of [
    ['2024-02-29', '45', Date.UTC(2024, 1, 29, 0, 45)],
    ['2026-07-16', '0', Date.UTC(2026, 6, 16)],
  ]) {
    assert.equal(acquisitionMsUtc(date, time), expected);
  }
});
