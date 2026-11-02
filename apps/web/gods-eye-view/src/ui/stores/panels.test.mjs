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

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createPinia } from 'pinia';
import { usePanelStore } from './panels.js';

test('the panel store reports each side’s open panel and keeps unchanged sides', () => {
  const store = usePanelStore(createPinia());
  const left = [
    { id: 'data-panel', open: false, available: true },
    { id: 'scene-panel', open: true, available: true },
  ];
  store.setSide('left', left);
  store.setSide('right', [
    { id: 'weather-panel', open: true, available: false },
  ]);
  assert.equal(store.openPanelId('left'), 'scene-panel');
  // An open panel that is not offered is not the side's open panel.
  assert.equal(store.openPanelId('right'), null);
  assert.equal(store.isOpen('scene-panel'), true);
  assert.equal(store.isOpen('data-panel'), false);
  const published = store.sides.left;
  store.setSide(
    'left',
    left.map((panel) => ({ ...panel })),
  );
  assert.equal(store.sides.left, published);
});
