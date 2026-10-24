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
import test from 'node:test';
import { PanelPositionControls } from './panelPositionControls.js';

/** A localStorage stand-in whose keys enumerate like the real one. */
function fakeStorage(entries) {
  const storage = {};
  Object.defineProperties(storage, {
    getItem: { value: (key) => (key in storage ? storage[key] : null) },
    setItem: { value: (key, value) => (storage[key] = String(value)) },
    removeItem: { value: (key) => delete storage[key] },
  });
  Object.assign(storage, entries);
  return storage;
}

test('the floating panels’ stored positions and hint flag are dropped; collapse state stays', (t) => {
  const saved = globalThis.localStorage;
  globalThis.localStorage = fakeStorage({
    'godsEyeView.v8.panelPos.cctv-panel': '{"x":1}',
    'godsEyeView.v8.panelFloatHintShown': '1',
    'godsEyeView.v6.panelCollapsed.cctv-panel': '1',
    'godsEyeView.v8.layoutResetNotified': '1',
  });
  t.after(() => {
    globalThis.localStorage = saved;
  });
  const controls = new PanelPositionControls({ showToast() {} });
  controls._maybeNotifyLayoutReset();
  assert.deepEqual(Object.keys(globalThis.localStorage).sort(), [
    'godsEyeView.v6.panelCollapsed.cctv-panel',
    'godsEyeView.v8.layoutResetNotified',
  ]);
});
