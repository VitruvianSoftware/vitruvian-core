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
import { validateValue } from './schema.js';
test('tool string schemas count Unicode characters rather than UTF-16 units', () => {
  const value = '𠮷野家😀';
  assert.deepEqual(validateValue({ type: 'string', maxLength: 4 }, value), []);
  assert.equal(
    validateValue({ type: 'string', minLength: 5 }, value).length,
    1,
  );
  assert.equal(
    validateValue({ type: 'string', maxLength: 3 }, value).length,
    1,
  );
  assert.deepEqual(
    validateValue({ type: 'string', minLength: 4, maxLength: 4 }, 'abcd'),
    [],
  );
  assert.equal(validateValue({ type: 'string', minLength: 2 }, '𠮷').length, 1);
});

test('tool string bounds hold at their edges and on huge arguments', () => {
  const string = (bounds) => ({ type: 'string', ...bounds });
  assert.deepEqual(validateValue(string({ maxLength: 3 }), '😀😀😀'), []);
  assert.equal(validateValue(string({ maxLength: 3 }), '😀😀😀😀').length, 1);
  assert.deepEqual(validateValue(string({ minLength: 3 }), '😀😀😀'), []);
  assert.deepEqual(validateValue(string({}), 'x'.repeat(1e6)), []);
  // Counting all of it takes roughly 0.7 s; stopping at the limit takes none.
  const huge = 'x'.repeat(1e8);
  const started = performance.now();
  assert.equal(validateValue(string({ maxLength: 60 }), huge).length, 1);
  assert.ok(performance.now() - started < 200, 'stops counting past the limit');
});
