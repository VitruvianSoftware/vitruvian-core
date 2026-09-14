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

// src/data/aircraftMeta.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { stickyText, stickyNumber } from './aircraftMeta.js';

test('stickyText holds last non-empty value', () => {
  assert.equal(stickyText('UAL123 ', undefined), 'UAL123');
  assert.equal(stickyText('', 'UAL123'), 'UAL123');
  assert.equal(stickyText('  ', 'UAL123'), 'UAL123');
  assert.equal(stickyText('DAL9', 'UAL123'), 'DAL9'); // new value wins
  assert.equal(stickyText(null, null), '');
});

test('stickyNumber holds last finite value, keeps 0, honors fallback', () => {
  assert.equal(stickyNumber(250, 100, 0), 250);
  assert.equal(stickyNumber(null, 100, 0), 100);
  assert.equal(stickyNumber(0, 100, 7), 0);        // 0 is a REAL value
  assert.equal(stickyNumber(NaN, undefined, 7), 7);
  assert.equal(stickyNumber(undefined, undefined, null), null);
});
