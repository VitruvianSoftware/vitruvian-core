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

/**
 * Military-registry active-transition tests (pre-ship audit M2).
 *
 * Locks the setMilitaryLayerActive contract the flights layer's immediate
 * suppression/restore sweep depends on: listeners fire only on TRANSITIONS
 * (never on same-value sets), after the new state is committed, and a broken
 * listener can't break the toggle.
 */

import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  setMilitaryLayerActive,
  isMilitaryLayerActive,
  onMilitaryLayerActiveChange,
} from './militaryRegistry.js';

test('active-change listener fires on transitions only, with committed state', () => {
  const seen = [];
  const unsub = onMilitaryLayerActiveChange((active) => {
    seen.push({ active, committed: isMilitaryLayerActive() });
  });
  try {
    setMilitaryLayerActive(false); // same value (initial false) → no fire
    assert.equal(seen.length, 0);

    setMilitaryLayerActive(true); // transition → fire, state already committed
    assert.deepEqual(seen, [{ active: true, committed: true }]);

    setMilitaryLayerActive(true); // same value → no fire
    assert.equal(seen.length, 1);

    setMilitaryLayerActive(false); // transition back → fire
    assert.deepEqual(seen[1], { active: false, committed: false });
    assert.equal(seen.length, 2);
  } finally {
    unsub();
    setMilitaryLayerActive(false);
  }
});

test('unsubscribe stops delivery; throwing listeners never break the toggle', () => {
  let calls = 0;
  const unsubBroken = onMilitaryLayerActiveChange(() => { throw new Error('boom'); });
  const unsubCounter = onMilitaryLayerActiveChange(() => { calls++; });
  try {
    setMilitaryLayerActive(true); // broken listener swallowed, counter still runs
    assert.equal(calls, 1);
    assert.equal(isMilitaryLayerActive(), true);

    unsubCounter();
    setMilitaryLayerActive(false);
    assert.equal(calls, 1); // unsubscribed → no more deliveries
  } finally {
    unsubBroken();
    unsubCounter();
    setMilitaryLayerActive(false);
  }
});

test('onMilitaryLayerActiveChange tolerates non-function listeners', () => {
  const unsub = onMilitaryLayerActiveChange(null);
  assert.equal(typeof unsub, 'function');
  unsub(); // no-op, must not throw
  setMilitaryLayerActive(true);
  assert.equal(isMilitaryLayerActive(), true);
  setMilitaryLayerActive(false);
});
