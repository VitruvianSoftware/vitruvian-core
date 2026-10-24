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
import { test } from 'node:test';
import { renderRadioState } from './radioPresentation.js';

function el() {
  const attrs = new Map();
  return {
    textContent: '',
    hidden: false,
    disabled: false,
    style: {},
    dataset: {},
    classList: { toggle() {}, add() {}, remove() {}, contains: () => false },
    setAttribute: (k, v) => attrs.set(k, String(v)),
    getAttribute: (k) => attrs.get(k),
    attrs,
  };
}

for (const lifecycleState of ['enabling', 'disabling']) {
  test(`Radio render survives the ${lifecycleState} transition`, () => {
    const prior = globalThis.document;
    globalThis.document = { getElementById: () => null };
    try {
      const enable = el();
      const ctx = {
        destroyed: false,
        _radioPanel: el(),
        _radioEnableBtn: enable,
        _syncContextRadioLauncherState() {},
        actions: {
          getLifecycle: () => ({
            lifecycleState,
            enabled: lifecycleState === 'disabling',
            uncertain: false,
          }),
        },
      };
      const state = {
        enabled: false,
        categories: [],
        filteredCount: 0,
        stationCount: 0,
        audioState: 'idle',
      };
      try {
        renderRadioState.call(ctx, state);
      } catch (error) {
        // Anything thrown after the transitional label is a different
        // missing fixture field, not the bug under test.
        assert.ok(
          !(
            error instanceof ReferenceError &&
            /lifecycleLabel/.test(error.message)
          ),
          `render threw: ${error.message}`,
        );
      }
      assert.equal(enable.attrs.get('aria-busy'), 'true');
      assert.equal(enable.textContent, lifecycleState.toUpperCase());
    } finally {
      globalThis.document = prior;
    }
  });
}
