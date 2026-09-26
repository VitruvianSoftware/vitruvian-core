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
import { createSourceSlot } from './sourceSlot.js';

test('replacing a source rejects its late result and old cleanup cannot clear the new source', async () => {
  let finish;
  const slot = createSourceSlot({ read: async () => 'default' }, ['read']);
  const old = slot.configure({ read: () => new Promise(resolve => { finish = resolve; }) });
  const pending = slot.source.read();
  const stop = slot.configure({ read: async () => 'replacement', attribution: { name: 'Replacement' } });
  old();
  finish('stale');
  await assert.rejects(pending, { name: 'AbortError' });
  assert.equal(await slot.source.read(), 'replacement');
  assert.equal(slot.source.attribution.name, 'Replacement');
  stop();
  assert.throws(() => slot.source.read(), /not configured/);
});

test('an invalid replacement leaves the working source intact', async () => {
  const slot = createSourceSlot({ read: async () => 42 }, ['read']);
  assert.throws(() => slot.configure({}), TypeError);
  assert.equal(await slot.source.read(), 42);
});
