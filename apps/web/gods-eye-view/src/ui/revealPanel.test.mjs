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
import { StyleManager } from './applicationShell.js';

function reveal({ phone }) {
  const sheets = [];
  const scrolls = [];
  const panel = { scrollIntoView: (options) => scrolls.push(options) };
  const saved = globalThis.document;
  const savedMatchMedia = globalThis.matchMedia;
  globalThis.document = {
    getElementById: (id) => (id === 'street-level-panel' ? panel : null),
  };
  globalThis.matchMedia = (query) => ({
    matches: phone && query === '(max-width: 720px)',
  });
  try {
    StyleManager.prototype.revealPanel.call(
      { _mobileShell: { setSheet: (sheet) => sheets.push(sheet) } },
      'street-level-panel',
    );
  } finally {
    globalThis.document = saved;
    globalThis.matchMedia = savedMatchMedia;
  }
  return { sheets, scrolls };
}

test('revealing a panel opens its phone sheet and scrolls the panel into view', () => {
  const { sheets, scrolls } = reveal({ phone: true });
  assert.deepEqual(sheets, ['cameras']);
  // The panel sits below the sheet's first screen at 375×812.
  assert.deepEqual(scrolls, [{ block: 'nearest' }]);
});

test('revealing a panel above 720px neither opens a sheet nor scrolls the rail', () => {
  assert.deepEqual(reveal({ phone: false }), { sheets: [], scrolls: [] });
});
